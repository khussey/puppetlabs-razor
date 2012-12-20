# Class: razor
#
# Parameters:
#
#   [*usename*]: daemon service account, default razor.
#   [*directory*]: installation directory, default /opt/razor.
#   [*address*]: razor.ipxe chain address, and razor service listen address,
#                default: facter ipaddress.
#   [*persist_host*]: ip address of the database server.
#   [*persist_mode*]: mode of persistent storage.
#   [*mk_checkin_interval*]: mk checkin interval.
#   [*mk_name*]: Razor tinycore linux mk name.
#   [*mk_source*]: Razor tinycore linux mk iso file source (local or http).
#   [*git_source*]: razor repo source.
#   [*git_revision*]: razor repo revision.
#
# Actions:
#
#   Manages razor and it's dependencies ruby, nodejs, mongodb, tftp, and sudo.
#
# Requires:
#
#   * [apt module](https://github.com/puppetlabs/puppetlabs-apt)
#   * [Mongodb module](https://github.com/puppetlabs/puppetlabs-mongodb)
#   * [Node.js module](https://github.com/puppetlabs/puppetlabs-nodejs)
#   * [stdlib module](https://github.com/puppetlabs/puppetlabs-stdlib)
#   * [tftp module](https://github.com/puppetlabs/puppetlabs-tftp)
#   * [sudo module](https://github.com/saz/puppet-sudo)
#   * [PostgreSQL module](https://github.com/puppetlabs/puppet-postgresql)
#
# Usage:
#
#   class { 'razor':
#     directory    => '/usr/local/razor',
#   }
#
class razor (
  $username            = 'razor',
  $directory           = '/opt/razor',
  $address             = $::ipaddress,
  $persist_host        = '127.0.0.1',
  $persist_mode        = 'mongo',
  $mk_checkin_interval = '60',
  $mk_name             = 'rz_mk_prod-image.0.9.1.6.iso',
  $mk_source           = 'https://github.com/downloads/puppetlabs/Razor-Microkernel/rz_mk_prod-image.0.9.1.6.iso',
  $git_source          = 'http://github.com/puppetlabs/Razor.git',
  $git_revision        = 'master'
) {

  include sudo
  include 'razor::ruby'
  include 'razor::tftp'

  case $persist_mode {
    'mongo': {
      class { 'mongodb':
        enable_10gen => true,
      }
    }
    'postgres': {
      include postgresql::server
    }
    'memory': {
    }
    default: {
      fail("Unsupported persist_mode: ${persist_mode}")
    }
  }

  Class['razor::ruby'] -> Class['razor']
  # The relationship is here so users can deploy tftp separately.
  Class['razor::tftp'] -> Class['razor']

  class { 'razor::nodejs':
    directory => $directory,
  }

  user { $username:
    ensure => present,
    gid    => $username,
    home   => $directory,
  }

  group { $username:
    ensure => present,
  }

  sudo::conf { 'razor':
    priority => 10,
    content  => "${username} ALL=(root) NOPASSWD: /bin/mount, /bin/umount\n",
  }

  if ! defined(Package['git']) {
    package { 'git':
      ensure => present,
    }
  }

  vcsrepo { $directory:
    ensure   => latest,
    provider => git,
    source   => $git_source,
    revision => $git_revision,
    require  => Package['git'],
  }

  file { $directory:
    ensure  => directory,
    mode    => '0755',
    owner   => $username,
    group   => $username,
    require => Vcsrepo[$directory],
  }

  service { 'razor':
    ensure    => running,
    provider  => base,
    hasstatus => true,
    status    => "${directory}/bin/razor_daemon.rb status",
    start     => "${directory}/bin/razor_daemon.rb start",
    stop      => "${directory}/bin/razor_daemon.rb stop",
    require   => [
      File[$directory],
      Sudo::Conf['razor']
    ],
    subscribe => [
      Class['razor::nodejs'],
      Vcsrepo[$directory]
    ],
  }

  case $persist_mode {
    'mongo': {
      Service['razor'] -> Class['mongodb']
    }
    'postgres': {
      Service['razor'] -> Class['postgres::server']
    }
    'memory': {
    }
    default: {
      fail("Unsupported persist_mode: ${persist_mode}")
    }
  }

  file { '/usr/bin/razor':
    ensure  => file,
    owner   => '0',
    group   => '0',
    mode    => '0755',
    content => template('razor/razor.erb'),
    require => Vcsrepo[$directory],
  }

  if ! defined(Package['curl']) {
    package { 'curl':
      ensure => present,
    }
  }

  rz_image { $mk_name:
    ensure  => present,
    type    => 'mk',
    source  => $mk_source,
    require => [
      File['/usr/bin/razor'],
      Package['curl'],
      Service['razor']
    ],
  }

  file { "$directory/conf/razor_server.conf":
    ensure  => file,
    content => template('razor/razor_server.erb'),
    require => Vcsrepo[$directory],
    notify  => Service['razor'],
  }

}
