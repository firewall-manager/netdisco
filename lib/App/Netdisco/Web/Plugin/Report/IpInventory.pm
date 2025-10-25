# Netdisco IP地址清单报告插件
# 此模块提供IP地址清单统计功能，用于分析网络中IP地址的使用情况和历史记录
package App::Netdisco::Web::Plugin::Report::IpInventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use NetAddr::IP::Lite ':lower';
use POSIX qw/strftime/;

# 注册报告 - IP地址清单，支持CSV导出和API接口，包含多个API参数
register_report(
    {   category     => 'IP',  # IP类别
        tag          => 'ipinventory',
        label        => 'IP Inventory',
        provides_csv => 1,          # 支持CSV导出
        api_endpoint => 1,             # 支持API接口
        api_parameters => [            # API参数定义
          subnet => {
            description => 'IP Prefix to search',
            required => 1,             # 必需参数：IP前缀
          },
          daterange => {
            description => 'Date range to search',
            default => ('1970-01-01 to '. strftime('%Y-%m-%d', gmtime)),  # 默认日期范围
          },
          age_invert => {
            description => 'Results should NOT be within daterange',
            type => 'boolean',
            default => 'false',        # 年龄反转选项
          },
          limit => {
            description => 'Maximum number of historical records',
            enum => [qw/32 64 128 256 512 1024 2048 4096 8192/],
            default => '2048',         # 历史记录数量限制
          },
          never => {
            description => 'Include in the report IPs never seen',
            type => 'boolean',
            default => 'false',        # 包含从未见过的IP
          },
        ],
    }
);

# IP地址清单报告路由 - 提供网络中IP地址的详细清单和历史记录
get '/ajax/content/report/ipinventory' => require_login sub {

    # 默认设置为简单值以防止"搜索失败"错误
    (my $subnet = (param('subnet') || '0.0.0.0/32')) =~ s/\s//g;  # 移除空格
    $subnet = NetAddr::IP::Lite->new($subnet);
    $subnet = NetAddr::IP::Lite->new('0.0.0.0/32')
      if (! $subnet) or ($subnet->addr eq '0.0.0.0');  # 验证子网格式

    my $agenot = param('age_invert') || '0';  # 年龄反转参数

    # 处理日期范围参数
    my $daterange = param('daterange')
      || ('1970-01-01 to '. strftime('%Y-%m-%d', gmtime));
    my ( $start, $end ) = $daterange =~ /(\d+-\d+-\d+)/gmx;  # 提取开始和结束日期

    my $limit = param('limit') || 256;  # 记录数量限制
    my $never = param('never') || '0';  # 包含从未见过的IP
    my $order = [{-desc => 'age'}, {-asc => 'ip'}];  # 排序规则：按年龄降序，IP升序

    # 需要合理的限制以防止潜在的DoS攻击，特别是当'never'为真时
    # TODO: 需要更好的输入验证，包括JS和服务器端验证以提供用户反馈
    $limit = 8192 if $limit > 8192;

    # 查询设备IP记录 - 获取设备相关的IP地址信息
    my $rs1 = schema(vars->{'tenant'})->resultset('DeviceIp')->search(
        undef,
        {   join   => ['device', 'device_port'],  # 连接设备和设备端口表
            select => [
                'alias AS ip',                    # IP地址别名
                'device_port.mac as mac',         # MAC地址
                'creation AS time_first',         # 首次创建时间
                'device.last_discover AS time_last',  # 最后发现时间
                'dns',                            # DNS名称
                \'true AS active',               # 标记为活跃
                \'false AS node',                 # 标记为非节点
                \qq/replace( date_trunc( 'minute', age( LOCALTIMESTAMP, device.last_discover ) ) ::text, 'mon', 'month') AS age/,  # 计算年龄
                'device.vendor',                  # 设备厂商
                \'null AS nbname',                # NetBIOS名称为空
            ],
            as => [qw( ip mac time_first time_last dns active node age vendor nbname)],
        }
    )->hri;

    # 查询节点IP记录 - 获取节点相关的IP地址信息
    my $rs2 = schema(vars->{'tenant'})->resultset('NodeIp')->search(
        undef,
        {   join   => ['manufacturer', 'netbios'],  # 连接制造商和NetBIOS表
            columns   => [qw( ip mac time_first time_last dns active)],  # 基本字段
            '+select' => [ \'true AS node',         # 标记为节点
                           \qq/replace( date_trunc( 'minute', age( LOCALTIMESTAMP, me.time_last ) ) ::text, 'mon', 'month') AS age/,  # 计算年龄
                           'manufacturer.company',  # 制造商公司
                           'netbios.nbname',        # NetBIOS名称
                         ],
            '+as'     => [ 'node', 'age', 'vendor', 'nbname' ],
        }
    )->hri;

    # 查询节点NetBIOS记录 - 获取NetBIOS相关的节点信息
    my $rs3 = schema(vars->{'tenant'})->resultset('NodeNbt')->search(
        undef,
        {   join   => ['manufacturer'],  # 连接制造商表
            columns   => [qw( ip mac time_first time_last )],  # 基本字段
            '+select' => [
                \'null AS dns',          # DNS为空
                'active',                # 活跃状态
                \'true AS node',         # 标记为节点
                \qq/replace( date_trunc( 'minute', age( LOCALTIMESTAMP, time_last ) ) ::text, 'mon', 'month') AS age/,  # 计算年龄
                'manufacturer.company',  # 制造商公司
                'nbname'                 # NetBIOS名称
            ],
            '+as' => [ 'dns', 'active', 'node', 'age', 'vendor', 'nbname' ],
        }
    )->hri;

    # 合并三个结果集
    my $rs_union = $rs1->union( [ $rs2, $rs3 ] );

    # 如果包含从未见过的IP，添加CIDR IP范围查询
    if ( $never ) {
        $subnet = NetAddr::IP::Lite->new('0.0.0.0/32') if ($subnet->bits ne 32);

        # 查询CIDR范围内的所有IP地址（包括从未见过的）
        my $rs4 = schema(vars->{'tenant'})->resultset('Virtual::CidrIps')->search(
            undef,
            {   bind => [ $subnet->cidr ],  # 绑定子网CIDR
                columns   => [qw( ip mac time_first time_last dns active node age vendor nbname )],
            }
        )->hri;

        $rs_union = $rs_union->union( [$rs4] );  # 合并CIDR IP结果
    }

    # 子查询：按子网过滤并去重
    my $rs_sub = $rs_union->search(
        { ip => { '<<' => $subnet->cidr } },  # 过滤在子网范围内的IP
        {   select   => [
                \'DISTINCT ON (ip) ip',        # 按IP去重
                'mac',                         # MAC地址
                'dns',                         # DNS名称
                \qq/date_trunc('second', time_last) AS time_last/,    # 截断到秒的最后时间
                \qq/date_trunc('second', time_first) AS time_first/,  # 截断到秒的首次时间
                'active',                      # 活跃状态
                'node',                        # 节点标记
                'age',                         # 年龄
                'vendor',                      # 厂商
                'nbname'                       # NetBIOS名称
            ],
            as => [
                'ip',     'mac',  'dns', 'time_last', 'time_first',
                'active', 'node', 'age', 'vendor', 'nbname'
            ],
            order_by => [{-asc => 'ip'}, {-asc => 'dns'}, {-desc => 'active'}, {-asc => 'node'}],  # 排序规则
        }
    )->as_query;

    # 根据日期范围进行最终过滤
    my $rs;
    if ( $start and $end ) {
        $start = $start . ' 00:00:00';  # 开始时间设为当天开始
        $end   = $end . ' 23:59:59';    # 结束时间设为当天结束

        if ( $agenot ) {
            # 年龄反转：查找不在日期范围内的记录
            $rs = $rs_union->search(
                {   -or => [
                        time_first => [ undef ],           # 首次时间为空
                        time_last => [ { '<', $start }, { '>', $end } ]  # 最后时间在范围外
                    ]
                },
                { from => { me => $rs_sub }, }
            );
        }
        else {
            # 正常过滤：查找在日期范围内的记录
            $rs = $rs_union->search(
                {   -or => [
                      -and => [
                          time_first => undef,    # 首次时间为空
                          time_last  => undef,    # 最后时间为空
                      ],
                      -and => [
                          time_last => { '>=', $start },  # 最后时间在开始时间之后
                          time_last => { '<=', $end },     # 最后时间在结束时间之前
                      ],
                    ],
                },
                { from => { me => $rs_sub }, }
            );
        }
    }
    else {
        # 没有日期范围，使用子查询结果
        $rs = $rs_union->search( undef, { from => { me => $rs_sub }, } );
    }

    # 执行查询并应用排序和限制
    my @results = $rs->order_by($order)->limit($limit)->all;
    return unless scalar @results;  # 如果没有结果则返回

    # 根据请求类型返回不同格式的数据
    if ( request->is_ajax ) {
        # AJAX请求：返回JSON格式的HTML模板
        my $json = to_json( \@results );
        template 'ajax/report/ipinventory.tt', { results => $json }, { layout => 'noop' };
    }
    else {
        # 非AJAX请求：返回CSV格式数据
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/ipinventory_csv.tt', { results => \@results, }, { layout => 'noop' };
    }
};

1;
