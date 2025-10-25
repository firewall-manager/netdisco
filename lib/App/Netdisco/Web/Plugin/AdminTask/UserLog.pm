# Netdisco 用户活动日志管理插件
# 此模块提供用户活动日志的查看功能，用于监控用户的操作记录
package App::Netdisco::Web::Plugin::AdminTask::UserLog;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use App::Netdisco::Util::ExpandParams 'expand_hash';

use App::Netdisco::Web::Plugin;

# 注册管理任务 - 用户活动日志
register_admin_task(
    {   tag   => 'userlog',
        label => 'User Activity Log',
    }
);

# 用户日志数据路由 - 提供DataTables格式的用户日志数据
ajax '/ajax/control/admin/userlog/data' => require_role admin => sub {
    # 验证DataTables必需的draw参数
    send_error( 'Missing parameter', 400 )
        unless ( param('draw') && param('draw') =~ /\d+/ );

    # 获取用户日志结果集
    my $rs = schema(vars->{'tenant'})->resultset('UserLog');

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

# 用户日志内容路由 - 显示用户活动日志页面
ajax '/ajax/content/admin/userlog' => require_role admin => sub {
    content_type('text/html');
    # 渲染用户日志模板
    template 'ajax/admintask/userlog.tt', {}, { layout => undef };
};

1;
