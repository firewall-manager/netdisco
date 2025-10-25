# Netdisco 设备PoE状态报告插件
# 此模块提供以太网供电(PoE)状态统计功能，用于监控网络中PoE设备的供电状态
package App::Netdisco::Web::Plugin::Report::DevicePoeStatus;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use App::Netdisco::Util::ExpandParams 'expand_hash';

use App::Netdisco::Web::Plugin;

# 注册报告 - 设备PoE状态，支持CSV导出和API接口
register_report(
    {   category     => 'Device',  # 设备类别
        tag          => 'devicepoestatus',
        label        => 'Power over Ethernet (PoE) Status',
        provides_csv => 1,          # 支持CSV导出
        api_endpoint => 1,          # 支持API接口
    }
);

# 设备PoE状态数据路由 - 提供DataTables格式的PoE状态数据
get '/ajax/content/report/devicepoestatus/data' => require_login sub {
    # 验证DataTables必需的draw参数
    send_error( 'Missing parameter', 400 )
        unless ( param('draw') && param('draw') =~ /\d+/ );

    # 获取设备PoE状态虚拟结果集
    my $rs = schema(vars->{'tenant'})->resultset('Virtual::DevicePoeStatus');

    # 展开参数（用于DataTables处理）
    my $exp_params = expand_hash( scalar params );
    
    # 获取总记录数
    my $recordsTotal = $rs->count;
    
    # 获取过滤后的数据
    my @data = $rs->get_datatables_data($exp_params)->hri->all;
    
    # 获取过滤后的记录数
    my $recordsFiltered = $rs->get_datatables_filtered_count($exp_params);

    content_type 'application/json';
    # 返回DataTables格式的JSON数据
    return to_json(
        {   draw            => int( param('draw') ),        # DataTables请求标识
            recordsTotal    => int($recordsTotal),          # 总记录数
            recordsFiltered => int($recordsFiltered),       # 过滤后记录数
            data            => \@data,                       # 数据数组
        }
    );
};

# 设备PoE状态内容路由 - 显示设备PoE状态信息
get '/ajax/content/report/devicepoestatus' => require_login sub {

    # 根据请求类型返回不同格式的数据
    if ( request->is_ajax ) {
        # AJAX请求：返回HTML模板
        template 'ajax/report/devicepoestatus.tt', {}, { layout => 'noop' };
    }
    else {
        # 非AJAX请求：返回CSV格式数据
        my @results
            = schema(vars->{'tenant'})->resultset('Virtual::DevicePoeStatus')
            ->hri->all;

        return unless scalar @results;  # 如果没有结果则返回

        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/devicepoestatus_csv.tt',
            { results => \@results, }, { layout => 'noop' };
    }
};

1;
