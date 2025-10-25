# Netdisco 节点厂商清单报告插件
# 此模块提供节点厂商清单统计功能，用于分析网络中节点的厂商分布情况
package App::Netdisco::Web::Plugin::Report::NodeVendor;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use App::Netdisco::Util::ExpandParams 'expand_hash';

use App::Netdisco::Web::Plugin;

# 注册报告 - 节点厂商清单，支持CSV导出
register_report(
    {   category     => 'Node',  # 节点类别
        tag          => 'nodevendor',
        label        => 'Node Vendor Inventory',
        provides_csv => 1,        # 支持CSV导出
    }
);

# 模板前钩子 - 处理搜索侧边栏模板的选中项
hook 'before_template' => sub {
    my $tokens = shift;

    # 只对节点厂商相关路径生效
    return
        unless (
        request->path eq uri_for('/report/nodevendor')->path
        or index( request->path,
            uri_for('/ajax/content/report/nodevendor')->path ) == 0
        );

    # 用于在搜索侧边栏模板中设置选中项
    foreach my $opt (qw/vendor/) {
        my $p = (
            ref [] eq ref param($opt)  # 检查参数是否为数组引用
            ? param($opt)
            : ( param($opt) ? [ param($opt) ] : [] )  # 转换为数组引用
        );
        $tokens->{"${opt}_lkp"} = { map { $_ => 1 } @$p };  # 创建查找哈希
    }
};

# 节点厂商数据路由 - 提供DataTables格式的节点厂商数据
get '/ajax/content/report/nodevendor/data' => require_login sub {
    # 验证DataTables必需的draw参数
    send_error( 'Missing parameter', 400 )
        unless ( param('draw') && param('draw') =~ /\d+/ );

    # 获取厂商参数
    my $vendor = param('vendor');

    # 获取节点结果集
    my $rs = schema(vars->{'tenant'})->resultset('Node');

    # 处理厂商匹配（空白厂商转换为undef）
    my $match = $vendor eq 'blank' ? undef : $vendor;

    # 按厂商缩写搜索并连接相关表
    $rs = $rs->search( { 'manufacturer.abbrev' => $match },
        {   '+columns' => [qw/ device.dns device.name manufacturer.abbrev manufacturer.company /],  # 添加设备DNS、名称和厂商信息
            join       => [qw/ manufacturer device /],  # 连接厂商和设备表
            collapse   => 1,                            # 折叠重复记录
        });

    # 除非指定了归档选项，否则只查询活跃节点
    unless ( param('archived') ) {
        $rs = $rs->search( { -bool => 'me.active' } );
    }

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

# 节点厂商内容路由 - 显示节点厂商清单信息
get '/ajax/content/report/nodevendor' => require_login sub {

    # 获取厂商参数
    my $vendor = param('vendor');

    # 获取节点结果集
    my $rs = schema(vars->{'tenant'})->resultset('Node');
    my @results;
    
    # 如果指定了厂商且不是AJAX请求，执行厂商过滤搜索
    if ( defined $vendor && !request->is_ajax ) {

        # 处理厂商匹配（空白厂商转换为undef）
        my $match = $vendor eq 'blank' ? undef : $vendor;

        # 按厂商缩写搜索并连接相关表
        $rs = $rs->search( { 'manufacturer.abbrev' => $match },
            {   '+columns' => [qw/ device.dns device.name manufacturer.abbrev manufacturer.company /],  # 添加设备DNS、名称和厂商信息
                join       => [qw/ manufacturer device /],  # 连接厂商和设备表
                collapse   => 1,                            # 折叠重复记录
            });

        # 除非指定了归档选项，否则只查询活跃节点
        unless ( param('archived') ) {
            $rs = $rs->search( { -bool => 'me.active' } );
        }

        @results = $rs->hri->all;
        return unless scalar @results;  # 如果没有结果则返回
    }
    # 如果没有指定厂商，显示厂商统计
    elsif ( !defined $vendor ) {
        # 查询厂商统计
        $rs = $rs->search(
            { },
            {   join     => 'manufacturer',  # 连接厂商表
                select   => [ 'manufacturer.abbrev', 'manufacturer.company', { count => {distinct => 'me.mac'}} ],  # 选择厂商缩写、公司名和MAC地址计数
                as       => [qw/ abbrev vendor count /],  # 字段别名
                group_by => [qw/ manufacturer.abbrev manufacturer.company /]  # 按厂商缩写和公司名分组
            }
        )->order_by( { -desc => 'count' } );  # 按计数降序排列

        # 除非指定了归档选项，否则只查询活跃节点
        unless ( param('archived') ) {
            $rs = $rs->search( { -bool => 'me.active' } );
        }
        
        @results = $rs->hri->all;
        return unless scalar @results;  # 如果没有结果则返回
    }

    # 根据请求类型返回不同格式的数据
    if ( request->is_ajax ) {
        # AJAX请求：返回JSON格式的HTML模板
        my $json = to_json( \@results );
        template 'ajax/report/nodevendor.tt',
            { results => $json, opt => $vendor },
            { layout => 'noop' };
    }
    else {
        # 非AJAX请求：返回CSV格式数据
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/nodevendor_csv.tt',
            { results => \@results, opt => $vendor },
            { layout => 'noop' };
    }
};

1;
