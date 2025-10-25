# Netdisco 设备SNMP管理插件
# 此模块提供SNMP数据浏览功能，包括SNMP树查看、OID搜索和MIB对象管理
package App::Netdisco::Web::Plugin::Device::SNMP;

use strict;
use warnings;

use Dancer qw(:syntax);
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Swagger;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::SNMP 'decode_and_munge';
use Module::Load ();
use Try::Tiny;

# 注册设备标签页 - SNMP管理页面
register_device_tab({tag => 'snmp', label => 'SNMP'});

# SNMP内容页面路由 - 需要用户登录
get '/ajax/content/device/snmp' => require_login sub {

  # 根据设备查询参数查找设备，如果找不到则返回错误
  my $device = try {
    schema(vars->{'tenant'})->resultset('Device')->search_for_device(param('q'))
  } or send_error('Bad Device', 404);

  # 渲染SNMP页面模板
  template 'ajax/device/snmp.tt', {device => $device->ip}, {layout => 'noop'};
};

# SNMP树数据路由 - 需要用户登录
ajax '/ajax/data/device/:ip/snmptree/:base' => require_login sub {

  # 根据IP地址查找设备，如果找不到则返回错误
  my $device = try {
    schema(vars->{'tenant'})->resultset('Device')->find(param('ip'))
  } or send_error('Bad Device', 404);

  # 获取OID基础路径并验证格式
  my $base = param('base');
  $base =~ m/^\.1(\.\d+)*$/ or send_error('Bad OID Base', 404);

  content_type 'application/json';

  # 检查设备是否有OID数据
  return to_json [{
    text     => 'No data for this device. Admins can request a snapshot in the Details tab.',
    children => \0,
    state    => {disabled => \1},
    icon     => 'icon-search',
  }]
    unless $device->oids->count;

  # 快照应该运行loadmibs，但以防万一没有发生...
  return to_json [{
    text     => 'No MIB objects. Please run a loadmibs job.',
    children => \0,
    state    => {disabled => \1},
    icon     => 'icon-search',
  }]
    unless schema(vars->{'tenant'})->resultset('SNMPObject')->count();

  # 获取SNMP数据并返回JSON
  my $items = _get_snmp_data($device->ip, $base);
  to_json $items;
};

# SNMP自动完成数据路由 - 需要用户登录
ajax '/ajax/data/snmp/typeahead' => require_login sub {

  # 获取搜索词，如果没有则返回空数组
  my $term = param('term') or return to_json [];

  # 获取设备和设备专用参数
  my $device     = param('ip');
  my $deviceonly = param('deviceonly');

  # 解析MIB和叶子节点
  my ($mib, $leaf) = split m/::/, $term;

  # 搜索SNMP对象
  my @found = schema(vars->{'tenant'})->resultset('SNMPObject')->search(
    {
      -or => [
        'me.oid' => $term,                        # 精确OID匹配
        'me.oid' => {-like => ($term . '.%')},    # OID前缀匹配
        -and     => [(
            ($mib and $leaf)
          ? ('me.mib' => $mib, 'me.leaf' => {-ilike => ($leaf . '%')})
          : ('me.leaf' => {-ilike => ('%' . $term . '%')})
        )]
      ],    # MIB和叶子匹配
      (($device and $deviceonly) ? ('device_browser.ip' => $device, 'device_browser.value' => {-not => undef}) : ())
    },    # 设备专用过滤
    {
      select   => [\q{ me.mib || '::' || me.leaf }],    # 选择MIB::叶子格式
      as       => ['qleaf'],
      join     => 'device_browser',
      rows     => 25,
      order_by => 'me.oid_parts'
    }
  )->get_column('qleaf')->all;

  return to_json [] unless scalar @found;

  # 返回排序后的结果
  content_type 'application/json';
  to_json [sort @found];
};

# SNMP节点搜索路由 - 需要用户登录
ajax '/ajax/data/snmp/nodesearch' => require_login sub {

  # 获取搜索字符串，如果没有则返回空数组
  my $to_match   = param('str') or return to_json [];
  my $partial    = param('partial');                    # 部分匹配标志
  my $device     = param('ip');                         # 设备IP
  my $deviceonly = param('deviceonly');                 # 仅设备标志

  # 解析MIB和叶子节点
  my ($mib, $leaf) = split m/::/, $to_match;
  my $found = undef;

  # 根据是否部分匹配选择不同的搜索策略
  if ($partial) {

    # 部分匹配：使用LIKE操作符
    $found = schema(vars->{'tenant'})->resultset('SNMPObject')->search(
      {
        -or => [
          'me.oid' => $to_match,                        # 精确OID匹配
          'me.oid' => {-like => ($to_match . '.%')},    # OID前缀匹配
          -and     => [(
              ($mib and $leaf)
            ? ('me.mib' => $mib, 'me.leaf' => {-ilike => ($leaf . '%')})
            : ('me.leaf' => {-ilike => ($to_match . '%')})
          )]
        ],    # MIB和叶子匹配
        (($device and $deviceonly) ? ('device_browser.ip' => $device, 'device_browser.value' => {-not => undef}) : ())
        ,     # 设备专用过滤
      },
      {rows => 1, join => 'device_browser', order_by => 'oid_parts'}
    )->first;
  }
  else {
    # 精确匹配：使用等号操作符
    $found = schema(vars->{'tenant'})->resultset('SNMPObject')->search(
      {
        (
            ($mib and $leaf)
          ? (-and => ['me.mib' => $mib, 'me.leaf' => $leaf])    # MIB和叶子精确匹配
          : (-or => ['me.oid' => $to_match, 'me.leaf' => $to_match])
        ),                                                      # OID或叶子精确匹配
        (($device and $deviceonly) ? ('device_browser.ip' => $device, 'device_browser.value' => {-not => undef}) : ())
        ,                                                       # 设备专用过滤
      },
      {rows => 1, join => 'device_browser', order_by => 'oid_parts'}
    )->first;
  }
  return to_json [] unless $found;

  # 构建OID路径数组
  $found = $found->oid;
  $found =~ s/^\.1\.?//;    # 移除开头的.1
  my @results = ('.1');

  # 逐部分构建完整OID路径
  foreach my $part (split m/\./, $found) {
    my $last = $results[-1];
    push @results, "${last}.${part}";
  }

  # 返回OID路径数组
  content_type 'application/json';
  to_json \@results;
};

# SNMP节点内容路由 - 需要用户登录
ajax '/ajax/content/device/:ip/snmpnode/:oid' => require_login sub {

  # 根据IP地址查找设备，如果找不到则返回错误
  my $device = try {
    schema(vars->{'tenant'})->resultset('Device')->find(param('ip'))
  } or send_error('Bad Device', 404);

  # 获取OID参数并验证格式
  my $oid = param('oid');
  $oid =~ m/^\.1(\.\d+)*$/ or send_error('Bad OID', 404);

  # 查找SNMP对象，包括过滤器信息
  my $object
    = schema(vars->{'tenant'})
    ->resultset('SNMPObject')
    ->find({'me.oid' => $oid}, {join => ['snmp_filter'], prefetch => ['snmp_filter']})
    or send_error('Bad OID', 404);

  # 获取数据处理函数名称
  my $munge = (param('munge') || ($object->snmp_filter ? $object->snmp_filter->subname : undef));

  # 查找设备浏览器中的值（这有点懒，可以通过上面的连接优化）
  my $value = schema(vars->{'tenant'})->resultset('DeviceBrowser')->search({
    -and => [
      -bool => \q{ array_length(oid_parts, 1) IS NOT NULL },    # OID部分不为空
      -bool => \q{ jsonb_typeof(value) = 'array' }
    ]
    })    # 值为数组类型
    ->find({'me.oid' => $oid, 'me.ip' => $device});

  # 构建数据哈希
  my %data = (
    $object->get_columns,                                                                 # 对象列数据
    snmp_object => {$object->get_columns},                                                # SNMP对象数据
    value       => (defined $value ? decode_and_munge($munge, $value->value) : undef),    # 解码和处理后的值
  );

  # 获取所有可用的数据处理函数
  my @mungers
    = schema(vars->{'tenant'})
    ->resultset('SNMPFilter')
    ->search({}, {distinct => 1, order_by => 'subname'})
    ->get_column('subname')
    ->all;

  # 渲染SNMP节点模板
  template 'ajax/device/snmpnode.tt', {node => \%data, munge => $munge, mungers => \@mungers}, {layout => 'noop'};
};

# 获取SNMP数据的辅助函数
sub _get_snmp_data {
  my ($ip, $base, $recurse) = @_;

  # 解析OID基础路径
  my @parts = grep {length} split m/\./, $base;

  # 查询过滤后的SNMP对象元数据
  my %meta
    = map { ('.' . join '.', @{$_->{oid_parts}}) => $_ }
    schema(vars->{'tenant'})->resultset('Virtual::FilteredSNMPObject')->search(
    {},
    {
      bind => [
        $ip,                    # 设备IP
        (scalar @parts + 1),    # 最小深度
        (scalar @parts + 1),    # 最大深度
        $base,                  # OID基础
      ]
    }
    )->hri->all;

  # 构建树形结构项目
  my @items = map { {
    id        => $_,
    mib       => $meta{$_}->{mib},                                                   # 通过node.original.mib访问
    leaf      => $meta{$_}->{leaf},                                                  # 通过node.original.leaf访问
    text      => ($meta{$_}->{leaf} . ' (' . $meta{$_}->{oid_parts}->[-1] . ')'),    # 显示文本
    has_value => $meta{$_}->{browser},                                               # 是否有值

    # 根据是否有浏览器数据设置图标
    ($meta{$_}->{browser} ? (icon => 'icon-folder-close text-info') : (icon => 'icon-folder-close-alt muted')),

    # 如果有索引则添加表格图标
    (scalar @{$meta{$_}->{index}} ? (icon => 'icon-th' . ($meta{$_}->{browser} ? ' text-info' : ' muted')) : ()),

    # 如果是叶子节点则添加叶子图标
    (
      (
        $meta{$_}->{num_children} == 0
          and ($meta{$_}->{type} or $meta{$_}->{access} =~ m/^(?:read|write)/ or $meta{$_}->{oid_parts}->[-1] == 0)
      ) ? (icon => 'icon-leaf' . ($meta{$_}->{browser} ? ' text-info' : ' muted')) : ()
    ),

    # jstree将异步调用展开这些，虽然我们可以通过调用_get_snmp_data()
    # 并传递给children来预取，但用户体验会慢很多。异步对搜索特别有用
    children => ($meta{$_}->{num_children} ? \1 : \0),

    # 设置显示为打开以显示单个子项
    # 但只有在下面有数据时才这样做
    state => {opened => (($meta{$_}->{browser} and $meta{$_}->{num_children} == 1) ? \1 : \0)},

  } } sort { $meta{$a}->{oid_parts}->[-1] <=> $meta{$b}->{oid_parts}->[-1] } keys %meta;

  return \@items;
}

true;
