# Netdisco 设备IP无DNS记录报告插件
# 此模块提供没有DNS记录的设备IP地址统计功能，用于识别网络中缺少DNS解析的设备
package App::Netdisco::Web::Plugin::Report::DeviceAddrNoDNS;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - 设备IP无DNS记录，支持CSV导出和API接口
register_report(
    {   category     => 'Device',  # 设备类别
        tag          => 'deviceaddrnodns',
        label        => 'IPs without DNS Entries',
        provides_csv => 1,          # 支持CSV导出
        api_endpoint => 1,          # 支持API接口
    }
);

# 设备IP无DNS记录报告路由 - 查找没有DNS记录的设备IP地址
get '/ajax/content/report/deviceaddrnodns' => require_login sub {
    # 查询没有DNS记录的设备IP地址
    my @results = schema(vars->{'tenant'})->resultset('Device')->search(
        { 'device_ips.dns' => undef },  # DNS字段为空
        {   
            select       => [ 'ip', 'dns', 'name', 'location', 'contact' ],  # 选择设备基本信息
            join         => [qw/device_ips/],  # 连接设备IP表
            '+columns' => [ { 'alias' => 'device_ips.alias' }, ],  # 添加IP别名字段
            order_by => { -asc => [qw/me.ip device_ips.alias/] },  # 按IP地址和别名升序排列
        }
    )->hri->all;

    return unless scalar @results;  # 如果没有结果则返回

    # 根据请求类型返回不同格式的数据
    if ( request->is_ajax ) {
        # AJAX请求：返回JSON格式的HTML模板
        my $json = to_json (\@results);
        template 'ajax/report/deviceaddrnodns.tt', { results => $json }, { layout => 'noop' };
    }
    else {
        # 非AJAX请求：返回CSV格式数据
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/deviceaddrnodns_csv.tt',
            { results => \@results, }, { layout => 'noop' };
    }
};

1;
