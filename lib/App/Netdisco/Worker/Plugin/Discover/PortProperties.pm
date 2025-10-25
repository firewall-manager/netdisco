# Netdisco端口属性发现插件
# 此模块提供端口属性发现功能，用于通过SNMP获取网络设备的端口属性信息
package App::Netdisco::Worker::Plugin::Discover::PortProperties;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use Dancer::Plugin::DBIC 'schema';

use Encode;
use App::Netdisco::Util::Web 'sort_port';
use App::Netdisco::Util::Permission 'acl_matches';
use App::Netdisco::Util::PortAccessEntity 'update_pae_attributes';
use App::Netdisco::Util::FastResolver 'hostnames_resolve_async';
use App::Netdisco::Util::Device qw/is_discoverable match_to_setting/;

# 注册主阶段工作器 - 发现端口属性
register_worker(
  {phase => 'main', driver => 'snmp'},    # 主阶段，使用SNMP驱动
  sub {
    my ($job, $workerconf) = @_;

    my $device = $job->device;
    return unless $device->in_storage;    # 确保设备已存储
    my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
      or return Status->defer("discover failed: could not SNMP connect to $device");

    my $interfaces = $snmp->interfaces || {};    # 获取接口映射
    my %properties = ();                         # 端口属性哈希

    # 缓存设备端口以节省数据库查询
    my $device_ports = vars->{'device_ports'} || {map { ($_->port => $_) } $device->ports->all};

    # 获取远程IP地址列表
    my @remote_ips = map { {ip => $_->remote_ip, port => $_->port} } grep { $_->remote_ip } values %$device_ports;

    # 异步解析远程IP地址的主机名
    debug sprintf ' [%s] resolving %d remote_ips with max %d outstanding requests', $device->ip, scalar @remote_ips,
      $ENV{'PERL_ANYEVENT_MAX_OUTSTANDING_DNS'};

    my $resolved_remote_ips = hostnames_resolve_async(\@remote_ips);
    $properties{$_->{port}}->{remote_dns} = $_->{dns} for @$resolved_remote_ips;

    # 获取原始速度信息
    my $raw_speed = $snmp->i_speed_raw || {};

    foreach my $idx (keys %$raw_speed) {
      my $port = $interfaces->{$idx} or next;
      if (!defined $device_ports->{$port}) {
        debug sprintf ' [%s] properties/speed - local port %s already skipped, ignoring', $device->ip, $port;
        next;
      }

      $properties{$port}->{raw_speed} = $raw_speed->{$idx};    # 设置原始速度
    }

    # 获取错误禁用原因
    my $err_cause = $snmp->i_err_disable_cause || {};

    foreach my $idx (keys %$err_cause) {
      my $port = $interfaces->{$idx} or next;
      if (!defined $device_ports->{$port}) {
        debug sprintf ' [%s] properties/errdis - local port %s already skipped, ignoring', $device->ip, $port;
        next;
      }

      $properties{$port}->{error_disable_cause} = $err_cause->{$idx};    # 设置错误禁用原因
    }

    # 获取快速启动状态
    my $faststart = $snmp->i_faststart_enabled || {};

    foreach my $idx (keys %$faststart) {
      my $port = $interfaces->{$idx} or next;
      if (!defined $device_ports->{$port}) {
        debug sprintf ' [%s] properties/faststart - local port %s already skipped, ignoring', $device->ip, $port;
        next;
      }

      $properties{$port}->{faststart} = $faststart->{$idx};    # 设置快速启动状态
    }

    # 获取LLDP/CDP信息
    my $c_if       = $snmp->c_if       || {};    # CDP接口
    my $c_cap      = $snmp->c_cap      || {};    # CDP能力
    my $c_platform = $snmp->c_platform || {};    # CDP平台

    # 获取LLDP远程设备信息
    my $rem_media_cap = $snmp->lldp_media_cap  || {};    # LLDP媒体能力
    my $rem_vendor    = $snmp->lldp_rem_vendor || {};    # LLDP远程厂商
    my $rem_model     = $snmp->lldp_rem_model  || {};    # LLDP远程型号
    my $rem_os_ver    = $snmp->lldp_rem_sw_rev || {};    # LLDP远程软件版本
    my $rem_serial    = $snmp->lldp_rem_serial || {};    # LLDP远程序列号

    # 处理LLDP/CDP邻居信息
    foreach my $idx (keys %$c_if) {
      my $port = $interfaces->{$c_if->{$idx}} or next;
      if (!defined $device_ports->{$port}) {
        debug sprintf ' [%s] properties/lldpcap - local port %s already skipped, ignoring', $device->ip, $port;
        next;
      }

      my $remote_cap  = $c_cap->{$idx} || [];                                  # 远程设备能力
      my $remote_type = Encode::decode('UTF-8', $c_platform->{$idx} || '');    # 远程设备类型

      # 初始化远程设备属性
      $properties{$port}->{remote_is_wap}          ||= 'false';                # 是否为无线接入点
      $properties{$port}->{remote_is_phone}        ||= 'false';                # 是否为电话
      $properties{$port}->{remote_is_discoverable} ||= 'true';                 # 是否可发现

      # 检查是否为无线接入点（通过平台类型）
      if (match_to_setting($remote_type, 'wap_platforms')) {
        $properties{$port}->{remote_is_wap} = 'true';
        debug sprintf ' [%s] properties/lldpcap - remote on port %s is a WAP by wap_platforms', $device->ip, $port;
      }

      # 检查是否为无线接入点（通过能力）
      if (scalar grep { match_to_setting($_, 'wap_capabilities') } @$remote_cap) {
        $properties{$port}->{remote_is_wap} = 'true';
        debug sprintf ' [%s] properties/lldpcap - remote on port %s is a WAP by wap_capabilities', $device->ip, $port;
      }

      # 检查是否为电话（通过平台类型）
      if (match_to_setting($remote_type, 'phone_platforms')) {
        $properties{$port}->{remote_is_phone} = 'true';
        debug sprintf ' [%s] properties/lldpcap - remote on port %s is a Phone by phone_platforms', $device->ip, $port;
      }

      # 检查是否为电话（通过能力）
      if (scalar grep { match_to_setting($_, 'phone_capabilities') } @$remote_cap) {
        $properties{$port}->{remote_is_phone} = 'true';
        debug sprintf ' [%s] properties/lldpcap - remote on port %s is a Phone by phone_capabilities', $device->ip,
          $port;
      }

      # 检查远程设备是否可发现
      if (!is_discoverable($device_ports->{$port}->remote_ip, $remote_type, $remote_cap)) {
        $properties{$port}->{remote_is_discoverable} = 'false';
        debug sprintf ' [%s] properties/lldpcap - remote on port %s is denied discovery', $device->ip, $port;
      }

      # 只有在支持库存信息时才获取远程设备详细信息
      next unless scalar grep { defined && m/^inventory$/ } @{$rem_media_cap->{$idx}};

      $properties{$port}->{remote_vendor} = $rem_vendor->{$idx};    # 远程厂商
      $properties{$port}->{remote_model}  = $rem_model->{$idx};     # 远程型号
      $properties{$port}->{remote_os_ver} = $rem_os_ver->{$idx};    # 远程操作系统版本
      $properties{$port}->{remote_serial} = $rem_serial->{$idx};    # 远程序列号
    }

    # 处理忽略设备端口配置
    if (scalar @{setting('ignore_deviceports')}) {
      foreach my $map (@{setting('ignore_deviceports')}) {
        next unless ref {} eq ref $map;                             # 跳过非哈希引用

        foreach my $key (sort keys %$map) {

          # 左侧匹配设备，右侧匹配端口
          next unless $key and $map->{$key};
          next unless acl_matches($device, $key);                   # 检查设备是否匹配

          foreach my $port (sort { sort_port($a, $b) } keys %properties) {
            next unless acl_matches([$properties{$port}, $device_ports->{$port}], $map->{$key});    # 检查端口是否匹配

            debug sprintf ' [%s] properties - removing %s (config:ignore_deviceports)', $device->ip, $port;
            $device_ports->{$port}->delete;                                                         # 从数据库中删除端口
            delete $properties{$port};                                                              # 从属性中删除端口
          }
        }
      }
    }

    # 设置接口索引
    foreach my $idx (keys %$interfaces) {
      next unless defined $idx;
      my $port = $interfaces->{$idx} or next;

      if (!defined $device_ports->{$port}) {
        debug sprintf ' [%s] properties/ifindex - local port %s already skipped, ignoring', $device->ip, $port;
        next;
      }

      # 验证接口索引是否为整数
      if ($idx !~ m/^[0-9]+$/) {
        debug sprintf ' [%s] properties/ifindex - port %s ifindex %s is not an integer', $device->ip, $port, $idx;
        next;
      }

      $properties{$port}->{ifindex} = $idx;    # 设置接口索引
    }

    # 如果没有端口属性要记录则返回
    return Status->info(" [$device] no port properties to record") unless scalar keys %properties;

    # 存储端口属性到数据库
    schema('netdisco')->txn_do(sub {
      my $gone = $device->properties_ports->delete;    # 删除现有端口属性

      debug sprintf ' [%s] properties - removed %d port properties', $device->ip, $gone;

      # 插入新的端口属性
      $device->properties_ports->populate([map { {port => $_, %{$properties{$_}}} } keys %properties]);

      debug sprintf ' [%s] properties - updating Port Access Entity', $device->ip;
      update_pae_attributes($device);                  # 更新端口访问实体属性

      return Status->info(sprintf ' [%s] properties - added %d new port properties', $device->ip,
        scalar keys %properties);
    });

  }
);

true;
