# Netdisco 端口搜索插件
# 此模块提供端口搜索功能，支持端口名称、VLAN和MAC地址搜索
package App::Netdisco::Web::Plugin::Search::Port;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::Port 'to_speed';
use App::Netdisco::Util::Web 'sql_match';

use Regexp::Common 'net';
use NetAddr::MAC ();

# 注册搜索标签页 - 端口搜索，支持CSV导出和API接口
register_search_tab({
  tag            => 'port',
  label          => 'Port',
  provides_csv   => 1,
  api_endpoint   => 1,
  api_parameters => [
    q        => {description => 'Port name, VLAN, or MAC address',             required => 1,},
    partial  => {description => 'Search for a partial match on parameter "q"', type => 'boolean', default => 'true',},
    uplink   => {description => 'Include uplinks in results',                  type => 'boolean', default => 'false',},
    descr    => {description => 'Search in the Port Description field',        type => 'boolean', default => 'false',},
    ethernet => {description => 'Only Ethernet type interfaces in results',    type => 'boolean', default => 'true',},
  ],
});

# 端口搜索路由 - 匹配描述（名称）的设备端口
get '/ajax/content/search/port' => require_login sub {

  # 获取查询参数
  my $q = param('q');
  send_error('Missing query', 400) unless $q;
  my $rs;

  # 检查是否为VLAN ID（数字且小于4096）
  if ($q =~ m/^[0-9]+$/ and $q < 4096) {

    # VLAN搜索：查找指定VLAN的端口
    $rs = schema(vars->{'tenant'})->resultset('DevicePort')->columns([qw/ ip port name up up_admin speed /])->search(
      {
        "port_vlans.vlan" => $q,    # VLAN ID匹配
        (
          param('uplink') ? () : (
            -or => [                # 如果不包含上行链路
              {-not_bool => "properties.remote_is_discoverable"},    # 远程不可发现
              {
                -or => [
                  {-not_bool      => "me.is_uplink"},    # 不是上行链路
                  {"me.is_uplink" => undef},             # 上行链路状态未定义
                ]
              }
            ]
          )
        ),
        (param('ethernet') ? ("me.type" => 'ethernetCsmacd') : ()),    # 以太网类型过滤
      },
      {'+columns' => [qw/ device.dns device.name port_vlans.vlan /], join => [qw/ properties port_vlans device /]}
    )->with_times;
  }
  else {
    # 其他搜索：端口名称、描述或MAC地址
    my ($likeval, $likeclause) = sql_match($q);
    my $mac = NetAddr::MAC->new(mac => ($q || ''));

    # 验证MAC地址格式
    undef $mac
      if (
      $mac and $mac->as_ieee and (
        ($mac->as_ieee eq '00:00:00:00:00:00')    # 无效MAC地址
        or ($mac->as_ieee !~ m/^$RE{net}{MAC}$/i)
      )
      );                                          # 不符合MAC格式

    # 构建复杂搜索条件
    $rs
      = schema(vars->{'tenant'})
      ->resultset('DevicePort')
      ->columns([qw/ ip port name up up_admin speed properties.remote_dns /])
      ->search(
      {
        -and => [
          -or => [
            {"me.name" => (param('partial') ? $likeclause : $q)},    # 端口名称匹配
            (
              param('descr')
              ? (                                                    # 如果搜索描述字段
                {"me.descr" => (param('partial') ? $likeclause : $q)},
                )
              : ()
            ),
            (
              ((!defined $mac) or $mac->errstr)                      # MAC地址搜索
              ? \['me.mac::text ILIKE ?', $likeval]                  # 文本搜索
              : {'me.mac' => $mac->as_ieee}                          # 精确MAC匹配
            ),
            {"properties.remote_dns" => $likeclause},                # 远程DNS匹配
            (
              param('uplink')
              ? (                                                    # 如果包含上行链路
                {"me.remote_id"   => $likeclause},                   # 远程ID匹配
                {"me.remote_type" => $likeclause},                   # 远程类型匹配
                )
              : ()
            ),
          ],
          (
            param('uplink') ? () : (
              -or => [    # 上行链路过滤
                {"properties.remote_dns" => $likeclause}, {-not_bool => "properties.remote_is_discoverable"},
                {-or                     => [{-not_bool => "me.is_uplink"}, {"me.is_uplink" => undef},]}
              ]
            )
          ),
          (param('ethernet') ? ("me.type" => 'ethernetCsmacd') : ()),    # 以太网类型过滤
        ]
      }, {
        '+columns' =>
          [qw/ device.dns device.name /, {vlan_agg => q{array_to_string(array_agg(port_vlans.vlan), ', ')}}],   # VLAN聚合
        join     => [qw/ properties port_vlans device /],
        group_by => [
          qw/me.ip me.port me.name me.up me.up_admin me.speed device.dns device.name device.last_discover device.uptime properties.remote_dns/
        ],
      }
      )->with_times;
  }

  # 获取搜索结果
  my @results = $rs->hri->all;
  return unless scalar @results;

  # 格式化端口速度显示
  map { $_->{speed} = to_speed($_->{speed}) } @results;

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/search/port.tt', {results => $json}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/search/port_csv.tt', {results => \@results}, {layout => 'noop'};
  }
};

1;
