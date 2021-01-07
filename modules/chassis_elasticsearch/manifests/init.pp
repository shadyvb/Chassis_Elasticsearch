# Create an Elasticsearch class
class chassis_elasticsearch(
  $config
) {
  if ( ! empty( $config[disabled_extensions] ) and 'chassis/chassis_elasticsearch' in $config[disabled_extensions] ) {
    service { 'elasticsearch':
      ensure => stopped,
      before => Class['elasticsearch']
    }
    class { 'elasticsearch':
      ensure => 'absent'
    }
    package { 'java-common':
        ensure => 'absent'
    }
  } else {
    include ::java
    # Default settings for install
    $defaults = {
      'repo_version' => '5',
      'version'      => '5.6.16',
      'plugins'      => [
        'analysis-icu'
      ],
      'host'         => '0.0.0.0',
      'port'         => 9200,
      'timeout'      => 30,
      # Ensure Java doesn't try to eat all the RAMs by default
      'memory'       => 256,
      'jvm_options'  => [],
    }

    # Allow override from config.yaml
    $options = deep_merge($defaults, $config[elasticsearch])

    # Ensure memory is an integer
    $memory = Integer($options[memory])

    # Create default jvm_options using memory setting
    $jvm_options_defaults = [
      "-Xms${memory}m",
      "-Xmx${memory}m",
      '-XX:+UseG1GC',
      '8:-XX:NumberOfGCLogFiles=32',
      '8:-XX:GCLogFileSize=64m',
      '8:-XX:+UseGCLogFileRotation',
      '8:-Xloggc:/var/log/elasticsearch/es/gc.log',
      '8:-XX:+PrintGCDetails',
      '8:-XX:+PrintTenuringDistribution',
      '8:-XX:+PrintGCDateStamps',
      '8:-XX:+PrintGCApplicationStoppedTime',
      '8:-XX:+UseConcMarkSweepGC',
      '8:-XX:+UseCMSInitiatingOccupancyOnly',
      '11:-XX:InitiatingHeapOccupancyPercent=75'
    ]

    # Merge JVM options using our custom function
    $jvm_options = merge_jvm_options($options[jvm_options], $jvm_options_defaults)

    # Support legacy repo version values.
    $repo_version = regsubst($options[repo_version], '^(\d+).*', '\\1')

    class { 'elastic_stack::repo':
      version => Integer($repo_version),
      notify  => Exec['apt_update']
    }

    # Install Elasticsearch
    class { 'elasticsearch':
      manage_repo       => true,
      version           => $options[version],
      jvm_options       => $jvm_options,
      api_protocol      => 'http',
      api_host          => $options[host],
      api_port          => $options[port],
      api_timeout       => $options[timeout],
      config            => {
        'network.host'  => '0.0.0.0',
        'discovery.type' => 'single-node',
        'discovery.seed_hosts' => []
      },
      restart_on_change => true,
      status            => enabled
    }

    # Install plugins
    elasticsearch::plugin { $options[plugins]: }

    # Ensure a dummy index is missing; this ensures the ES connection is
    # running before we try installing.
    elasticsearch::index { 'chassis-validate-es-connection':
      ensure  => 'absent',
      require => [
        Elasticsearch::Plugin[ $options[plugins] ],
      ],
      before  => Chassis::Wp[ $config['hosts'][0] ],
    }

    # Create shared config directory and give write permissions to web server.
    $package_symlinks = [ "/etc/elasticsearch/config" ]

    file { '/usr/share/elasticsearch/config':
      ensure  => directory,
      owner   => 'elasticsearch',
      group   => 'www-data',
      mode    => '0777',
    }

    file { $package_symlinks:
      ensure  => link,
      target  => '/usr/share/elasticsearch/config',
      require => File['/usr/share/elasticsearch/config']
    }
  }
}
