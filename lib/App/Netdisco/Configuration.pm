package App::Netdisco::Configuration;

use App::Netdisco::Environment;
use App::Netdisco::Util::DeviceAuth ();
use Dancer ':script';

use FindBin;
use File::Spec;
use Path::Class 'dir';
use Net::Domain 'hostdomain';
use AnyEvent::Loop; # avoid EV
use File::ShareDir 'dist_dir';
use Storable 'dclone';
use URI::Based;

BEGIN {
  if (setting('include_paths') and ref [] eq ref setting('include_paths')) {
    # 将有用的位置添加到@INC中
    push @{setting('include_paths')},
         dir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'nd-site-local', 'lib')->stringify
      if (setting('site_local_files'));
    unshift @INC, @{setting('include_paths')};
  }
}

BEGIN {
  no warnings 'redefine';
  use SNMP;

  # 在macOS上至少当translateObj接收到像'.0.0'这样的参数时会出现硬件异常

  my $orig_translate = *SNMP::translateObj{'CODE'};
  *SNMP::translateObj = sub {
    my $arg = $_[0];
    return undef unless defined $arg and $arg !~ m/^[.0]+$/;
    return $orig_translate->(@_);
  };
}

# 从简单配置变量设置数据库模式配置
if (ref {} eq ref setting('database')) {
    # 从环境变量覆盖（用于docker）

    setting('database')->{name} =
      ($ENV{NETDISCO_DB_NAME} || $ENV{NETDISCO_DBNAME} || $ENV{PGDATABASE} || setting('database')->{name});

    setting('database')->{host} =
      ($ENV{NETDISCO_DB_HOST} || $ENV{PGHOST} || setting('database')->{host});

    my $portnum = ($ENV{NETDISCO_DB_PORT} || $ENV{PGPORT});
    setting('database')->{host} .= (';port='. $portnum)
      if (setting('database')->{host} and $portnum);
    # 曾经我们要求用户添加port=
    setting('database')->{host} =~ s/port=port=/port=/ if $portnum;

    setting('database')->{user} =
      ($ENV{NETDISCO_DB_USER} || $ENV{PGUSER} || setting('database')->{user});

    setting('database')->{pass} =
      ($ENV{NETDISCO_DB_PASS} || $ENV{PGPASSWORD} || setting('database')->{pass});

    my $name = setting('database')->{name};
    my $host = setting('database')->{host};
    my $user = setting('database')->{user};
    my $pass = setting('database')->{pass};

    my $dsn = sprintf 'dbi:Pg:dbname=%s', ($name || '');
    $dsn .= ";host=${host}" if $host;

    # 现在我们有配置访问权限，设置netdisco模式
    # 但只有在早期配置样式中不存在时才设置
    setting('plugins')->{DBIC}->{'default'} ||= {
        dsn  => $dsn,
        user => $user,
        password => $pass,
        options => {
            AutoCommit => 1,
            RaiseError => 1,
            auto_savepoint => 1,
            pg_enable_utf8 => 1,
        },
        schema_class => 'App::Netdisco::DB',
    };

    foreach my $c (@{setting('tenant_databases')}) {
        my $schema = $c->{tag} or next;
        next if exists setting('plugins')->{DBIC}->{$schema};

        my $name = $c->{name} || $c->{tag};
        my $host = $c->{host};
        my $user = $c->{user};
        my $pass = $c->{pass};

        my $dsn = "dbi:Pg:dbname=${name}";
        $dsn .= ";host=${host}" if $host;

        setting('plugins')->{DBIC}->{$schema} = {
          dsn  => $dsn,
          user => $user,
          password => $pass,
          options => {
              AutoCommit => 1,
              RaiseError => 1,
              auto_savepoint => 1,
              pg_enable_utf8 => 1,
          },
          schema_class => 'App::Netdisco::DB',
        };
    }

    # 通过设置默认模式指向的内容来支持租户
    setting('plugins')->{DBIC}->{'netdisco'}->{'alias'} = 'default';

    # 允许覆盖默认租户
    setting('plugins')->{DBIC}->{'default'}
     = setting('plugins')->{DBIC}->{$ENV{NETDISCO_DB_TENANT}}
     if $ENV{NETDISCO_DB_TENANT}
        and $ENV{NETDISCO_DB_TENANT} ne 'netdisco'
        and exists setting('plugins')->{DBIC}->{$ENV{NETDISCO_DB_TENANT}};

    # 激活环境变量，以便可以调用"psql"
    # 也可以被python工作单元使用来连接（避免重新解析配置）
    # 必须在租户之后发生，因为如果NETDISCO_DB_TENANT在起作用，这会重写环境
    my $default = setting('plugins')->{DBIC}->{'default'};
    if ($default->{dsn} =~ m/dbname=([^;]+)/) {
        $ENV{PGDATABASE} = $1;
    }
    if ($default->{dsn} =~ m/host=([^;]+)/) {
        $ENV{PGHOST} = $1;
    }
    if ($default->{dsn} =~ m/port=(\d+)/) {
        $ENV{PGPORT} = $1;
    }
    $ENV{PGUSER} = $default->{user};
    $ENV{PGPASSWORD} = $default->{password};
    $ENV{PGCLIENTENCODING} = 'UTF8';

    foreach my $c (@{setting('external_databases')}) {
        my $schema = delete $c->{tag} or next;
        next if exists setting('plugins')->{DBIC}->{$schema};
        setting('plugins')->{DBIC}->{$schema} = $c;
        setting('plugins')->{DBIC}->{$schema}->{schema_class}
          ||= 'App::Netdisco::GenericDB';
    }
}

# 总是设置这个
$ENV{DBIC_TRACE_PROFILE} = 'console';

# 从环境变量覆盖（用于docker）
config->{'community'} = ($ENV{NETDISCO_RO_COMMUNITY} ?
  [split ',', $ENV{NETDISCO_RO_COMMUNITY}] : config->{'community'});
config->{'community_rw'} = ($ENV{NETDISCO_RW_COMMUNITY} ?
  [split ',', $ENV{NETDISCO_RW_COMMUNITY}] : config->{'community_rw'});

# 如果snmp_auth和device_auth未设置，添加默认值到community{_rw}
if ((setting('snmp_auth') and 0 == scalar @{ setting('snmp_auth') })
    and (setting('device_auth') and 0 == scalar @{ setting('device_auth') })) {
  config->{'community'} = [ @{setting('community')}, 'public' ];
  config->{'community_rw'} = [ @{setting('community_rw')}, 'private' ];
}
# 修复device_auth（或从旧的snmp_auth和community设置创建）
# 也导入遗留的sshcollector配置
config->{'device_auth'}
  = [ App::Netdisco::Util::DeviceAuth::fixup_device_auth() ];

# 工作进程的默认值
setting('workers')->{queue} ||= 'PostgreSQL';
if ($ENV{ND2_SINGLE_WORKER}) {
  setting('workers')->{tasks} = 1;
  delete config->{'schedule'};
}

# 如果未设置，强制跳过DNS解析
setting('dns')->{hosts_file} ||= '/etc/hosts';
setting('dns')->{no} ||= ['fe80::/64','169.254.0.0/16'];

# 为AnyEvent::DNS设置最大未完成请求数
$ENV{'PERL_ANYEVENT_MAX_OUTSTANDING_DNS'}
  = setting('dns')->{max_outstanding} || 50;
$ENV{'PERL_ANYEVENT_HOSTS'} = setting('dns')->{hosts_file};

# 加载/etc/hosts
setting('dns')->{'ETCHOSTS'} = {};
{
  # AE::DNS::EtcHosts只适用于A/AAAA/SRV，但我们想要PTR
  # 这使用AE加载+解析/etc/hosts文件。脏技巧。
  use AnyEvent::Loop;
  use AnyEvent::Socket 'format_address';
  use AnyEvent::DNS::EtcHosts;
  AnyEvent::DNS::EtcHosts::_load_hosts_unless(sub{},AE::cv);
  no AnyEvent::DNS::EtcHosts; # 取消导入

  setting('dns')->{'ETCHOSTS'}->{$_} =
    [ map { [ $_ ? (format_address $_->[0]) : '' ] }
          @{ $AnyEvent::DNS::EtcHosts::HOSTS{ $_ } } ]
    for keys %AnyEvent::DNS::EtcHosts::HOSTS;
}

# 从环境变量覆盖（用于docker）
if ($ENV{NETDISCO_DOMAIN}) {
  if ($ENV{NETDISCO_DOMAIN} eq 'discover') {
    delete $ENV{NETDISCO_DOMAIN};
    if (! setting('domain_suffix')) {
      info '正在解析域名...';
      config->{'domain_suffix'} = hostdomain;
    }
  }
  else {
    config->{'domain_suffix'} = $ENV{NETDISCO_DOMAIN};
  }
}

# 从环境变量覆盖SNMP bulkwalk
config->{'bulkwalk_off'} = true
  if (exists $ENV{NETDISCO_SNMP_BULKWALK_OFF} and $ENV{NETDISCO_SNMP_BULKWALK_OFF});

# 检查用户的port_control_reasons

config->{'port_control_reasons'} =
  config->{'port_control_reasons'} || config->{'system_port_control_reasons'};

# 用于管理数据库portctl_roles

config->{'portctl_by_role_shadow'}
  = dclone (setting('portctl_by_role') || {});

# 将domain_suffix从标量或列表转换为正则表达式

config->{'domain_suffix'} = [setting('domain_suffix')]
  if ref [] ne ref setting('domain_suffix');

if (scalar @{ setting('domain_suffix') }) {
  my @suffixes = map { (ref qr// eq ref $_) ? $_ : quotemeta }
                    @{ setting('domain_suffix') };
  my $buildref = '(?:'. (join '|', @suffixes) .')$';
  config->{'domain_suffix'} = qr/$buildref/;
}
else {
  config->{'domain_suffix'} = qr//;
}

# 将expire_devices从单个值转换为字典

if (q{} eq ref setting('expire_devices')) {
  config->{'expire_devices'}
    = { 'group:__ANY__' => setting('expire_devices') };
}

# 将tacacs从单个值转换为列表

if (ref {} eq ref setting('tacacs')
  and exists setting('tacacs')->{'key'}) {

  config->{'tacacs'} = [
    Host => setting('tacacs')->{'server'},
    Key  => setting('tacacs')->{'key'} || setting('tacacs')->{'secret'},
    Port => (setting('tacacs')->{'port'} || 'tacacs'),
    Timeout => (setting('tacacs')->{'timeout'} || 15),
  ];
}
elsif (ref [] eq ref setting('tacacs')) {
  my @newservers = ();
  foreach my $server (@{ setting('tacacs') }) {
    push @newservers, [
      Host => $server->{'server'},
      Key  => $server->{'key'} || $server->{'secret'},
      Port => ($server->{'port'} || 'tacacs'),
      Timeout => ($server->{'timeout'} || 15),
    ];
  }
  config->{'tacacs'} = [ @newservers ];
}

# 支持无序字典，就像它们是单个项目列表一样

if (ref {} eq ref setting('device_identity')) {
  config->{'device_identity'} = [ setting('device_identity') ];
}
else { config->{'device_identity'} ||= [] }

if (ref {} eq ref setting('macsuck_no_deviceport')) {
  config->{'macsuck_no_deviceports'} = [ setting('macsuck_no_deviceport') ];
}
if (ref {} eq ref setting('macsuck_no_deviceports')) {
  config->{'macsuck_no_deviceports'} = [ setting('macsuck_no_deviceports') ];
}
else { config->{'macsuck_no_deviceports'} ||= [] }

if (ref {} eq ref setting('hide_deviceports')) {
  config->{'hide_deviceports'} = [ setting('hide_deviceports') ];
}
else { config->{'hide_deviceports'} ||= [] }

if (ref {} eq ref setting('ignore_deviceports')) {
  config->{'ignore_deviceports'} = [ setting('ignore_deviceports') ];
}
else { config->{'ignore_deviceports'} ||= [] }

# 将旧的ignore_*复制到新设置中
if (scalar @{ config->{'ignore_interfaces'} }) {
  config->{'host_groups'}->{'__IGNORE_INTERFACES__'}
    = [ map { ($_ !~ m/^port:/) ? "port:$_" : $_ } @{ config->{'ignore_interfaces'} } ];
}
if (scalar @{ config->{'ignore_interface_types'} }) {
  config->{'host_groups'}->{'__IGNORE_INTERFACE_TYPES__'}
    = [ map { ($_ !~ m/^type:/) ? "type:$_" : $_ } @{ config->{'ignore_interface_types'} } ];
}
if (scalar @{ config->{'ignore_notpresent_types'} }) {
  config->{'host_groups'}->{'__NOTPRESENT_TYPES__'}
    = [ map { ($_ !~ m/^type:/) ? "type:$_" : $_ } @{ config->{'ignore_notpresent_types'} } ];
}

# 将devices_no和devices_only复制到其他设置中
foreach my $name (qw/devices_no devices_only
                    discover_no macsuck_no arpnip_no nbtstat_no
                    discover_only macsuck_only arpnip_only nbtstat_only/) {
  config->{$name} ||= [];
  config->{$name} = [setting($name)] if ref [] ne ref setting($name);
}
foreach my $name (qw/discover_no macsuck_no arpnip_no nbtstat_no/) {
  push @{setting($name)}, @{ setting('devices_no') };
}
foreach my $name (qw/discover_only macsuck_only arpnip_only nbtstat_only/) {
  push @{setting($name)}, @{ setting('devices_only') };
}

# 遗留配置项名称

# 将snmp_field_protection重命名为field_protection
config->{'field_protection'} = config->{'snmp_field_protection'}
  if exists config->{'snmp_field_protection'};

# 如果用户之前将too_many_devices从1000默认值配置为其他值，
# 则将其复制到netmap_performance_limit_max_devices
config->{'netmap_performance_limit_max_devices'} =
  config->{'sidebar_defaults'}->{'device_netmap'}->{'too_many_devices'}->{'default'}
  if config->{'sidebar_defaults'}->{'device_netmap'}->{'too_many_devices'}->{'default'}
    and config->{'sidebar_defaults'}->{'device_netmap'}->{'too_many_devices'}->{'default'} != 1000;
delete config->{'sidebar_defaults'}->{'device_netmap'}->{'too_many_devices'};

config->{'devport_vlan_limit'} =
  config->{'deviceport_vlan_membership_threshold'}
  if setting('deviceport_vlan_membership_threshold')
     and not setting('devport_vlan_limit');
delete config->{'deviceport_vlan_membership_threshold'};

# portctl_native_vlan以前叫做vlanctl
config->{'portctl_native_vlan'} ||= config->{'vlanctl'};
delete config->{'vlanctl'};

config->{'schedule'} = config->{'housekeeping'}
  if setting('housekeeping') and not setting('schedule');
delete config->{'housekeeping'};

# 以前有不同类型的工作进程
if (exists setting('workers')->{interactives}
    or exists setting('workers')->{pollers}) {

    setting('workers')->{tasks} ||=
      (setting('workers')->{pollers} || 0)
      + (setting('workers')->{interactives} || 0);

    delete setting('workers')->{pollers};
    delete setting('workers')->{interactives};
}

# 移动了timeout设置
setting('workers')->{'timeout'} = setting('timeout')
  if defined setting('timeout')
     and !defined setting('workers')->{'timeout'};

# 工作进程的max_deferrals和retry_after为0就像禁用一样
# 但我们需要用特殊值来模拟它
setting('workers')->{'max_deferrals'} ||= (2**30);
setting('workers')->{'retry_after'}   ||= '100 years';

# schedule expire以前叫做expiry
setting('schedule')->{expire} ||= setting('schedule')->{expiry}
  if setting('schedule') and exists setting('schedule')->{expiry};
delete config->{'schedule'}->{'expiry'} if setting('schedule');

# 将报告配置从哈希升级到列表
if (setting('reports') and ref {} eq ref setting('reports')) {
    config->{'reports'} = [ map {{
        tag => $_,
        %{ setting('reports')->{$_} }
    }} keys %{ setting('reports') } ];
}

# 将system_reports添加到reports中
config->{'reports'} = [ @{setting('system_reports')}, @{setting('reports')} ];

# 将裸bind_params升级为字典
foreach my $r ( @{setting('reports')} ) {
    next unless exists $r->{bind_params};
    my $new_bind_params = [ map {ref $_ ? $_ : {param => $_}} @{ $r->{bind_params} } ];
    $r->{'bind_params'} = $new_bind_params;
}

# 设置swagger ui位置
#config->{plugins}->{Swagger}->{ui_dir} =
  #dir(dist_dir('App-Netdisco'), 'share', 'public', 'swagger-ui')->absolute;

# 为request->uri_for()不可用时设置助手
# （例如在swagger_path()内部时）
config->{url_base}
  = URI::Based->new((config->{path} eq '/') ? '' : config->{path});
config->{api_base}
  = config->{url_base}->with('/api/v1')->path;

# 带有snmp_object的设备custom_fields创建钩子
my @new_dcf = ();
my @new_hooks = @{ setting('hooks') };

foreach my $field (@{ setting('custom_fields')->{'device'} }) {
    next unless $field->{'name'};

    if (not exists $field->{'snmp_object'} or not $field->{'snmp_object'}) {
        push @new_dcf, $field;
        next;
    }

    # snmp_object意味着字段中的JSON内容
    $field->{'json_list'} = true;
    # snmp_object意味着用户不应该在web中编辑
    $field->{'editable'} = false;

    push @new_hooks, {
        type => 'exec',
        event => 'discover',
        with => {
                            # 获取snmp_object的JSON格式
            cmd => (sprintf q![%% ndo %%] show -d '[%% ip %%]' -e %s --quiet!
                            # 这个jq将：将null提升为[]，将裸字符串提升为["str"]，将对象折叠为列表
                            .q! | jq -cjM '. // [] | if type=="string" then [.] else . end | [ .[] ] | sort'!
                            # 将JSON输出发送到设备custom_field（内联操作）
                            .q! | [%% ndo %%] %s --enqueue -d '[%% ip %%]' -e '@-' --quiet!,
                            $field->{'snmp_object'}, ('cf_'. $field->{'name'})),
        },
        filter => {
            no => $field->{'no'},
            only => $field->{'only'},
        },
    };
    push @new_dcf, $field;
}

# #1040 将with-nodes更改为作业钩子
foreach my $action (qw(macsuck arpnip)) {
    push @new_hooks, {
        type => 'exec',
        event => 'new_device',
        with => {
            cmd => (sprintf q![%% ndo %%] %s --enqueue -d '[%% ip %%]' --quiet!, $action)
        }
    };
}

config->{'hooks'} = \@new_hooks;
config->{'custom_fields'}->{'device'} = \@new_dcf;

true;
