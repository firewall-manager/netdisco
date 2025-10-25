# Netdisco SSID清单报告插件
# 此模块提供SSID清单统计功能，用于分析网络中无线网络的SSID分布情况
package App::Netdisco::Web::Plugin::Report::SsidInventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - SSID清单，支持CSV导出和API接口
register_report(
    {   category     => 'Wireless',  # 无线类别
        tag          => 'ssidinventory',
        label        => 'SSID Inventory',
        provides_csv => 1,            # 支持CSV导出
        api_endpoint => 1,             # 支持API接口
    }
);

# SSID清单报告路由 - 显示SSID清单信息
get '/ajax/content/report/ssidinventory' => require_login sub {
    # 查询所有SSID信息
    my @results = schema(vars->{'tenant'})->resultset('DevicePortSsid')
        ->get_ssids->hri->all;  # 获取SSID列表

    return unless scalar @results;  # 如果没有结果则返回

    # 根据请求类型返回不同格式的数据
    if ( request->is_ajax ) {
        # AJAX请求：返回JSON格式的HTML模板
        my $json = to_json( \@results );
        template 'ajax/report/portssid.tt', { results => $json }, { layout => 'noop' };
    }
    else {
        # 非AJAX请求：返回CSV格式数据
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/portssid_csv.tt', { results => \@results }, { layout => 'noop' };
    }
};

1;
