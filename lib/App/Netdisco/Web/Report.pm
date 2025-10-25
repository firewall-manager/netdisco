package App::Netdisco::Web::Report;

# 报告Web模块
# 提供报告页面功能

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

# 报告页面路由
# 处理报告页面请求
get '/report/*' => require_login sub {
    my ($tag) = splat;

    # 用于报告搜索侧边栏填充选择输入
    my ( $domain_list, $class_list, $ssid_list, $type_list, $vendor_list );

    # 根据报告类型获取相应的数据列表
    if ( $tag eq 'netbios' ) {
        $domain_list = [ schema(vars->{'tenant'})->resultset('NodeNbt')
                ->get_distinct_col('domain') ];
    }
    elsif ( $tag eq 'moduleinventory' ) {
        $class_list = [ schema(vars->{'tenant'})->resultset('DeviceModule')
                ->get_distinct_col('class') ];
    }
    elsif ( $tag eq 'portssid' ) {
        $ssid_list = [ schema(vars->{'tenant'})->resultset('DevicePortSsid')
                ->get_distinct_col('ssid') ];
    }
    elsif ( $tag eq 'nodesdiscovered' ) {
        $type_list = [ schema(vars->{'tenant'})->resultset('DevicePort')
                ->get_distinct_col('remote_type') ];
    }
    elsif ( $tag eq 'nodevendor' ) {
        $vendor_list = [
            schema(vars->{'tenant'})->resultset('Node')->search(
                {},
                {   join     => 'manufacturer',
                    columns  => ['manufacturer.abbrev'],
                    order_by => 'manufacturer.abbrev',
                    group_by => 'manufacturer.abbrev',
                }
                )->get_column('abbrev')->all
        ];
    }

    # 让AJAX像标签页一样工作
    params->{tab} = $tag;

    var( nav => 'reports' );
    template 'report',
        {
        report      => setting('_reports')->{$tag},
        domain_list => $domain_list,
        class_list  => $class_list,
        ssid_list   => $ssid_list,
        type_list   => $type_list,
        vendor_list => $vendor_list,
        }, { layout => 'main' };
};

true;
