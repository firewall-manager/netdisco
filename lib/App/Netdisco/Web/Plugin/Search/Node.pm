# Netdisco 节点搜索插件
# 此模块提供节点搜索功能，支持MAC地址、IP地址和主机名搜索，包括时间范围过滤
package App::Netdisco::Web::Plugin::Search::Node;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use NetAddr::IP::Lite ':lower';
use Regexp::Common 'net';
use NetAddr::MAC ();
use POSIX qw/strftime/;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::DNS 'ipv4_from_hostname';
use App::Netdisco::Util::Web 'sql_match';

# 注册搜索标签页 - 节点搜索，支持API接口
register_search_tab({
    tag => 'node',
    label => 'Node',
    api_endpoint => 1,
    api_parameters => [
      q => {
        description => 'MAC Address or IP Address or Hostname (without Domain Suffix) of a Node (supports SQL or "*" wildcards)',
        required => 1,
      },
      partial => {
        description => 'Partially match the "q" parameter (wildcard characters not required)',
        type => 'boolean',
        default => 'false',
      },
      deviceports => {
        description => 'MAC Address search will include Device Port MACs',
        type => 'boolean',
        default => 'true',
      },
      show_vendor => {
        description => 'Include interface Vendor in results',
        type => 'boolean',
        default => 'false',
      },
      archived => {
        description => 'Include archived records in results',
        type => 'boolean',
        default => 'false',
      },
      daterange => {
        description => 'Date Range in format "YYYY-MM-DD to YYYY-MM-DD"',
        default => ('1970-01-01 to '. strftime('%Y-%m-%d', gmtime)),
      },
      age_invert => {
        description => 'Results should NOT be within daterange',
        type => 'boolean',
        default => 'false',
      },
      # mac_format is used only in the template (will be IEEE) in results
      #mac_format => {
      #},
      # stamps param is used only in the template (they will be included)
      #stamps => {
      #},
    ],
});

# 节点搜索路由 - 匹配IP、DNS主机名或MAC地址
get '/ajax/content/search/node' => require_login sub {
    # 获取节点查询参数
    my $node = param('q');
    send_error('Missing node', 400) unless $node;
    return unless ($node =~ m/\w/); # 需要至少一些字母数字字符
    content_type('text/html');

    # 获取时间范围参数
    my $agenot = param('age_invert') || '0';
    my ( $start, $end ) = param('daterange') =~ m/(\d+-\d+-\d+)/gmx;

    # 尝试解析MAC地址
    my $mac = NetAddr::MAC->new(mac => ($node || ''));
    undef $mac if
      ($mac and $mac->as_ieee
      and (($mac->as_ieee eq '00:00:00:00:00:00')  # 无效的MAC地址
        or ($mac->as_ieee !~ m/^$RE{net}{MAC}$/i)));  # 不符合MAC格式

    # 设置活动记录过滤条件
    my @active = (param('archived') ? () : (-bool => 'active'));
    my (@times, @wifitimes, @porttimes);

    # 处理时间范围过滤
    if ( $start and $end ) {
        $start = $start . ' 00:00:00';  # 开始时间设为当天开始
        $end   = $end   . ' 23:59:59';  # 结束时间设为当天结束

        if ($agenot) {
            # 反转时间过滤：排除指定时间范围内的记录
            @times = (-or => [
              time_first => [ undef ],                    # 没有首次时间
              time_last => [ { '<', $start }, { '>', $end } ]  # 最后时间在范围外
            ]);
            @wifitimes = (-or => [
              time_last => [ undef ],                     # 没有最后时间
              time_last => [ { '<', $start }, { '>', $end } ],  # 最后时间在范围外
            ]);
            @porttimes = (-or => [
              creation => [ undef ],                      # 没有创建时间
              creation => [ { '<', $start }, { '>', $end } ]    # 创建时间在范围外
            ]);
        }
        else {
            # 正常时间过滤：包含指定时间范围内的记录
            @times = (-or => [
              -and => [
                  time_first => undef,                    # 没有首次时间
                  time_last  => undef,                    # 没有最后时间
              ],
              -and => [
                  time_last => { '>=', $start },          # 最后时间在开始时间之后
                  time_last => { '<=', $end },            # 最后时间在结束时间之前
              ],
            ]);
            @wifitimes = (-or => [
              time_last  => undef,                        # 没有最后时间
              -and => [
                  time_last => { '>=', $start },          # 最后时间在开始时间之后
                  time_last => { '<=', $end },            # 最后时间在结束时间之前
              ],
            ]);
            @porttimes = (-or => [
              creation => undef,                          # 没有创建时间
              -and => [
                  creation => { '>=', $start },           # 创建时间在开始时间之后
                  creation => { '<=', $end },             # 创建时间在结束时间之前
              ],
            ]);
        }
    }

    # 处理SQL匹配和通配符
    my ($likeval, $likeclause) = sql_match($node, not param('partial'));
    my $using_wildcards = (($likeval ne $node) ? 1 : 0);

    # 构建MAC地址搜索条件
    my @where_mac =
      ($using_wildcards ? \['me.mac::text ILIKE ?', $likeval]  # 使用通配符搜索
                        : ((!defined $mac or $mac->errstr) ? \'0=1' : ('me.mac' => $mac->as_ieee)) );  # 精确MAC匹配

    # 查询节点目击记录
    my $sightings = schema(vars->{'tenant'})->resultset('Node')
      ->search({-and => [@where_mac, @active, @times]}, {
          order_by => {'-desc' => 'time_last'},  # 按最后时间降序排列
          '+columns' => [
            'device.dns',                        # 设备DNS名称
            'device.name',                       # 设备名称
            { time_first_stamp => \"to_char(time_first, 'YYYY-MM-DD HH24:MI')" },  # 首次时间戳
            { time_last_stamp =>  \"to_char(time_last, 'YYYY-MM-DD HH24:MI')" },   # 最后时间戳
          ],
          join => 'device',
      });

    # 查询节点IP记录
    my $ips = schema(vars->{'tenant'})->resultset('NodeIp')
      ->search({-and => [@where_mac, @active, @times]}, {
          order_by => {'-desc' => 'time_last'},
          '+columns' => [
            'manufacturer.company',              # 厂商公司名
            'manufacturer.abbrev',               # 厂商缩写
            { time_first_stamp => \"to_char(time_first, 'YYYY-MM-DD HH24:MI')" },
            { time_last_stamp =>  \"to_char(time_last, 'YYYY-MM-DD HH24:MI')" },
          ],
          join => 'manufacturer'
      })->with_router;

    # 查询NetBIOS记录
    my $netbios = schema(vars->{'tenant'})->resultset('NodeNbt')
      ->search({-and => [@where_mac, @active, @times]}, {
          order_by => {'-desc' => 'time_last'},
          '+columns' => [
            'manufacturer.company',
            'manufacturer.abbrev',
            { time_first_stamp => \"to_char(time_first, 'YYYY-MM-DD HH24:MI')" },
            { time_last_stamp =>  \"to_char(time_last, 'YYYY-MM-DD HH24:MI')" },
          ],
          join => 'manufacturer
      });

    # 查询无线记录
    my $wireless = schema(vars->{'tenant'})->resultset('NodeWireless')->search(
        { -and => [@where_mac, @wifitimes] },
        { order_by   => { '-desc' => 'time_last' },
          '+columns' => [
            'manufacturer.company',
            'manufacturer.abbrev',
            {
              time_last_stamp => \"to_char(time_last, 'YYYY-MM-DD HH24:MI')"
            }],
          join => 'manufacturer'
        }
    );

    # 查询设备端口记录
    my $rs_dp = schema(vars->{'tenant'})->resultset('DevicePort');
    
    # 如果找到MAC地址相关的记录，返回MAC搜索结果
    if ($sightings->has_rows or $ips->has_rows or $netbios->has_rows) {
        my $ports = param('deviceports')
          ? $rs_dp->search({ -and => [@where_mac] }, { order_by => { '-desc' => 'creation' }}) : undef;

        return template 'ajax/search/node_by_mac.tt', {
          ips       => $ips,        # IP记录
          sightings => $sightings,  # 目击记录
          ports     => $ports,     # 端口记录
          wireless  => $wireless,  # 无线记录
          netbios   => $netbios,   # NetBIOS记录
        }, { layout => 'noop' };
    }
    else {
        # 如果没有找到MAC相关记录，尝试端口搜索
        my $ports = param('deviceports')
          ? $rs_dp->search({ -and => [@where_mac, @porttimes] }, { order_by => { '-desc' => 'creation' }}) : undef;

        if (defined $ports and $ports->has_rows) {
            return template 'ajax/search/node_by_mac.tt', {
              ips       => $ips,
              sightings => $sightings,
              ports     => $ports,
              wireless  => $wireless,
              netbios   => $netbios,
            }, { layout => 'noop' };
        }
    }

    # 尝试其他搜索方法
    my $have_rows = 0;
    my $set = schema(vars->{'tenant'})->resultset('NodeNbt')
        ->search_by_name({nbname => $likeval, @active, @times});
    ++$have_rows if $set->has_rows;

    # 如果没有找到NetBIOS记录，尝试其他搜索方法
    unless ( $have_rows ) {
        # 检查是否为IP地址格式
        if ($node =~ m{^(?:$RE{net}{IPv4}|$RE{net}{IPv6})(?:/\d+)?$}i
            and my $ip = NetAddr::IP::Lite->new($node)) {

            # search_by_ip()会提取CIDR表示法（如果需要）
            $set = schema(vars->{'tenant'})->resultset('NodeIp')
              ->search_by_ip({ip => $ip, @active, @times})->with_router;
            ++$have_rows if $set->has_rows;
        }
        else {
            # 尝试DNS名称搜索
            $set = schema(vars->{'tenant'})->resultset('NodeIp')
              ->search_by_dns({
                  ($using_wildcards ? (dns => $likeval) :  # 通配符搜索
                                      (dns => "${likeval}.\%", suffix => setting('domain_suffix'))),  # 精确搜索
                  @active,
                  @times,
                })->with_router;
            ++$have_rows if $set->has_rows;

            # 尝试DNS解析作为后备方案
            if (not $using_wildcards and not $have_rows) {
                my $resolved_ip = ipv4_from_hostname($node);

                if ($resolved_ip) {
                    $set = schema(vars->{'tenant'})->resultset('NodeIp')
                      ->search_by_ip({ip => $resolved_ip, @active, @times})->with_router;
                    ++$have_rows if $set->has_rows;
                }
            }

            # 如果用户选择了厂商搜索选项，则尝试厂商公司名称作为后备方案
            if (param('show_vendor') and not $have_rows) {
                $set = schema(vars->{'tenant'})->resultset('NodeIp')
                  ->with_times
                  ->search(
                    {'manufacturer.company' => { -ilike => ''.sql_match($node)}, @times},  # 厂商公司名搜索
                    {'prefetch' => 'manufacturer'},
                  )->with_router;
                ++$have_rows if $set->has_rows;
            }
        }
    }

    # 如果没有找到任何记录，则返回
    return unless $set and ($have_rows or $set->has_rows);
    $set = $set->search_rs({}, { order_by => 'me.mac' });

    # 返回IP搜索结果模板
    return template 'ajax/search/node_by_ip.tt', {
      macs => $set,                    # MAC记录
      archive_filter => {@active},    # 归档过滤条件
    }, { layout => 'noop' };
};

true;
