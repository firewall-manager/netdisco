# Netdisco NetBIOS清单报告插件
# 此模块提供NetBIOS清单统计功能，用于分析网络中NetBIOS服务的分布和配置情况
package App::Netdisco::Web::Plugin::Report::Netbios;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use App::Netdisco::Util::ExpandParams 'expand_hash';

use App::Netdisco::Web::Plugin;

# 注册报告 - NetBIOS清单，支持CSV导出
register_report(
    {   category     => 'Node',  # 节点类别
        tag          => 'netbios',
        label        => 'NetBIOS Inventory',
        provides_csv => 1,        # 支持CSV导出
    }
);

# 模板前钩子 - 处理搜索侧边栏模板的选中项
hook 'before_template' => sub {
    my $tokens = shift;

    # 只对NetBIOS相关路径生效
    return
        unless ( request->path eq uri_for('/report/netbios')->path
        or
        index( request->path, uri_for('/ajax/content/report/netbios')->path )
        == 0 );

    # 用于在搜索侧边栏模板中设置选中项
    foreach my $opt (qw/domain/) {
        my $p = (
            ref [] eq ref param($opt)  # 检查参数是否为数组引用
            ? param($opt)
            : ( param($opt) ? [ param($opt) ] : [] )  # 转换为数组引用
        );
        $tokens->{"${opt}_lkp"} = { map { $_ => 1 } @$p };  # 创建查找哈希
    }
};

# NetBIOS数据路由 - 提供DataTables格式的NetBIOS数据
get '/ajax/content/report/netbios/data' => require_login sub {
    # 验证DataTables必需的draw参数
    send_error( 'Missing parameter', 400 )
        unless ( param('draw') && param('draw') =~ /\d+/ );

    # 获取域名参数
    my $domain = param('domain');

    # 获取NetBIOS节点结果集
    my $rs = schema(vars->{'tenant'})->resultset('NodeNbt');

    # 处理域名搜索（空白域名转换为空字符串）
    my $search = $domain eq 'blank' ? '' : $domain;
    $rs = $rs->search( { domain => $search } )  # 按域名过滤
        ->order_by( [ { -asc => 'domain' }, { -desc => 'time_last' } ] );  # 按域名升序，最后时间降序排列

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

# NetBIOS内容路由 - 显示NetBIOS清单信息
get '/ajax/content/report/netbios' => require_login sub {

    # 获取域名参数
    my $domain = param('domain');

    # 获取NetBIOS节点结果集
    my $rs = schema(vars->{'tenant'})->resultset('NodeNbt');
    my @results;

    # 如果指定了域名且不是AJAX请求，执行域名过滤搜索
    if ( defined $domain && !request->is_ajax ) {
        # 处理域名搜索（空白域名转换为空字符串）
        my $search = $domain eq 'blank' ? '' : $domain;
        @results
            = $rs->search( { domain => $search } )  # 按域名过滤
            ->order_by( [ { -asc => 'domain' }, { -desc => 'time_last' } ] )  # 按域名升序，最后时间降序排列
            ->hri->all;

        return unless scalar @results;  # 如果没有结果则返回
    }
    # 如果没有指定域名，显示域名统计
    elsif ( !defined $domain ) {
        # 查询域名统计
        @results = $rs->search(
            {},
            {   select   => [ 'domain', { count => 'domain' } ],  # 选择域名和计数
                as       => [qw/ domain count /],                  # 字段别名
                group_by => [qw/ domain /]                        # 按域名分组
            }
        )->order_by( { -desc => 'count' } )->hri->all;  # 按计数降序排列

        return unless scalar @results;  # 如果没有结果则返回
    }

    # 根据请求类型返回不同格式的数据
    if ( request->is_ajax ) {
        # AJAX请求：返回JSON格式的HTML模板
        my $json = to_json( \@results );
        template 'ajax/report/netbios.tt',
            { results => $json, opt => $domain },
            { layout => 'noop' };
    }
    else {
        # 非AJAX请求：返回CSV格式数据
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/netbios_csv.tt',
            { results => \@results, opt => $domain },
            { layout => 'noop' };
    }
};

1;
