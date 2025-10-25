# Netdisco 多节点端口报告插件
# 此模块提供连接多个节点的端口统计功能，用于识别网络中连接多个节点的端口
package App::Netdisco::Web::Plugin::Report::PortMultiNodes;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - 多节点端口，支持CSV导出和API接口，包含VLAN过滤参数
register_report(
    {   category     => 'Port',  # 端口类别
        tag          => 'portmultinodes',
        label        => 'Ports with multiple nodes attached',
        provides_csv => 1,          # 支持CSV导出
        api_endpoint => 1,          # 支持API接口
        api_parameters => [        # API参数定义
          vlan => {
            description => 'Filter by VLAN',  # 按VLAN过滤
            type => 'integer',
          },
        ],
    }
);

# 多节点端口报告路由 - 查找连接多个节点的端口
get '/ajax/content/report/portmultinodes' => require_login sub {
    # 查询连接多个节点的端口
    my @results = schema(vars->{'tenant'})->resultset('Device')->search(
        {   
            'ports.remote_ip' => undef,  # 端口没有远程IP（非上行端口）
            # 如果指定了VLAN参数，按VLAN过滤
            (param('vlan') ?
              ('ports.vlan' => param('vlan'), 'nodes.vlan' => param('vlan')) : ()),
            'nodes.active'    => 1,      # 节点为活跃状态
            'wireless.port'   => undef   # 不是无线端口
        },
        {   
            select => [ 'ip', 'dns', 'name' ],  # 选择设备基本信息
            join       => { 'ports' => [ 'wireless', 'nodes' ] },  # 连接端口、无线和节点表
            '+columns' => [
                { 'port'        => 'ports.port' },        # 端口号
                { 'description' => 'ports.name' },        # 端口描述
                { 'mac_count'   => { count => 'nodes.mac' } },  # MAC地址数量统计
            ],
            group_by => [qw/me.ip me.dns me.name ports.port ports.name/],  # 按设备和端口分组
            having   => \[ 'count(nodes.mac) > ?', [ count => 1 ] ],        # 过滤：MAC数量大于1
            order_by => { -desc => [qw/count/] },        # 按计数降序排列
        }
    )->hri->all;

    return unless scalar @results;  # 如果没有结果则返回

    # 根据请求类型返回不同格式的数据
    if ( request->is_ajax ) {
        # AJAX请求：返回JSON格式的HTML模板
        my $json = to_json (\@results);
        template 'ajax/report/portmultinodes.tt', { results => $json }, { layout => 'noop' };
    }
    else {
        # 非AJAX请求：返回CSV格式数据
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/portmultinodes_csv.tt',
            { results => \@results, }, { layout => 'noop' };
    }
};

1;
