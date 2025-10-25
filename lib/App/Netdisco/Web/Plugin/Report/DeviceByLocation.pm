# Netdisco 按位置分组的设备清单报告插件
# 此模块提供按位置分组的设备清单统计功能，用于按地理位置查看网络设备分布情况
package App::Netdisco::Web::Plugin::Report::DeviceByLocation;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - 按位置分组的设备清单，支持CSV导出和API接口
register_report(
    {   category     => 'Device',  # 设备类别
        tag          => 'devicebylocation',
        label        => 'Inventory by Location',
        provides_csv => 1,          # 支持CSV导出
        api_endpoint => 1,          # 支持API接口
    }
);

# 按位置分组的设备清单报告路由 - 按位置显示设备清单
get '/ajax/content/report/devicebylocation' => require_login sub {
    # 查询所有设备，选择特定字段并按位置排序
    my @results
        = schema(vars->{'tenant'})->resultset('Device')
        ->columns(  [qw/ ip dns name location vendor model /] )  # 选择设备基本信息字段
        ->order_by( [qw/ location name ip vendor model /] )->hri->all;  # 按位置、名称、IP、厂商、型号排序

    return unless scalar @results;  # 如果没有结果则返回

    # 根据请求类型返回不同格式的数据
    if ( request->is_ajax ) {
        # AJAX请求：返回JSON格式的HTML模板
        my $json = to_json( \@results );
        template 'ajax/report/devicebylocation.tt', { results => $json }, { layout => 'noop' };
    }
    else {
        # 非AJAX请求：返回CSV格式数据
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/devicebylocation_csv.tt',
            { results => \@results }, { layout => 'noop' };
    }
};

1;
