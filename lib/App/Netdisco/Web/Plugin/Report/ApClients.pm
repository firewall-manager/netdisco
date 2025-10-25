# Netdisco 接入点客户端数量报告插件
# 此模块提供无线接入点客户端数量统计功能，用于分析各接入点的客户端连接情况
package App::Netdisco::Web::Plugin::Report::ApClients;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - 接入点客户端数量，支持CSV导出和API接口
register_report(
    {   category     => 'Wireless',  # 无线类别
        tag          => 'apclients',
        label        => 'Access Point Client Count',
        provides_csv => 1,            # 支持CSV导出
        api_endpoint => 1,            # 支持API接口
    }
);

# 接入点客户端数量报告路由 - 统计各接入点的客户端连接数量
get '/ajax/content/report/apclients' => require_login sub {
    # 查询接入点客户端数量统计
    my @results = schema(vars->{'tenant'})->resultset('Device')->search(
        { 
          'nodes.time_last' => { '>=', \'me.last_macsuck' },  # 节点最后时间大于设备最后MAC收集时间
          'ports.port' => { '-in' => schema(vars->{'tenant'})->resultset('DevicePortWireless')->get_column('port')->as_query },  # 端口必须是无线端口
        },
        {   
            select => [ 'ip', 'model', 'ports.port', 'ports.name', 'ports.type' ],  # 选择设备信息
            join       => { 'ports' =>  'nodes' },  # 连接端口和节点表
            '+columns' => [
                { 'mac_count' => { count => 'nodes.mac' } },  # 计算MAC地址数量（客户端数量）
            ],
            group_by => [
                'me.ip', 'me.model', 'ports.port', 'ports.name', 'ports.type',  # 按设备和端口分组
            ],
            order_by => { -asc => [qw/ports.name ports.type/] },  # 按端口名称和类型升序排列
        }
    )->hri->all;

    return unless scalar @results;  # 如果没有结果则返回

    # 根据请求类型返回不同格式的数据
    if ( request->is_ajax ) {
        # AJAX请求：返回JSON格式的HTML模板
        my $json = to_json( \@results );
        template 'ajax/report/apclients.tt', { results => $json }, { layout => 'noop' };
    }
    else {
        # 非AJAX请求：返回CSV格式数据
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/apclients_csv.tt',
            { results => \@results }, { layout => 'noop' };
    }
};

1;
