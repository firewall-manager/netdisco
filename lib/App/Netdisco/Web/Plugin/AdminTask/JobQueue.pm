# Netdisco 作业队列管理插件
# 此模块提供作业队列监控和管理功能，包括作业删除和状态统计
package App::Netdisco::Web::Plugin::AdminTask::JobQueue;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::JobQueue qw/jq_log jq_delete/;

# 注册管理任务 - 作业队列管理
register_admin_task({
  tag => 'jobqueue',
  label => 'Job Queue',
});

# 删除单个作业路由
ajax '/ajax/control/admin/jobqueue/del' => require_role admin => sub {
    send_error('Missing job', 400) unless param('job');
    jq_delete( param('job') );  # 删除指定作业
};

# 删除所有作业路由
ajax '/ajax/control/admin/jobqueue/delall' => require_role admin => sub {
    jq_delete();  # 删除所有作业
};

# 数字格式化函数 - 添加千位分隔符
sub commify {
    my $text = reverse $_[0];  # 反转字符串
    $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;  # 每三位数字后添加逗号
    return scalar reverse $text;  # 反转回原顺序
}

# 作业队列内容路由 - 显示作业队列状态和统计信息
ajax '/ajax/content/admin/jobqueue' => require_role admin => sub {
    content_type('text/html');

    # 查询后端工作进程信息
    my @backends = schema(vars->{'tenant'})->resultset('DeviceSkip')
        ->search({device => '255.255.255.255'})->hri->all;  # 特殊设备IP表示后端进程

    my $num_backends = scalar @backends;  # 后端进程数量
    my $tot_workers  = 0;
    $tot_workers += $_->{deferrals} for @backends;  # 计算总工作进程数

    # 查询各种作业状态统计
    my $jq_locked = schema(vars->{'tenant'})->resultset('Admin')
      ->search({status => 'queued', backend => { '!=' => undef }})->count();  # 正在运行的作业

    my $jq_backlog = schema(vars->{'tenant'})->resultset('Admin')
      ->search({status => 'queued', backend => undef })->count();  # 等待队列中的作业

    my $jq_done = schema(vars->{'tenant'})->resultset('Admin')
      ->search({status => 'done'})->count();  # 已完成的作业

    my $jq_errored = schema(vars->{'tenant'})->resultset('Admin')
      ->search({status => 'error'})->count();  # 出错的作业

    # 查询过期作业（运行时间超过设定阈值的作业）
    my $jq_stale = schema(vars->{'tenant'})->resultset('Admin')->search({
        status => 'queued',
        backend => { '!=' => undef },
        started => \[q/<= (LOCALTIMESTAMP - ?::interval)/, setting('jobs_stale_after')],
    })->count();

    my $jq_total = schema(vars->{'tenant'})->resultset('Admin')->count();  # 总作业数

    # 渲染作业队列模板，传递统计信息
    template 'ajax/admintask/jobqueue.tt', {
      num_backends => commify($num_backends || '?'),  # 后端进程数（格式化）
      tot_workers  => commify($tot_workers || '?'),   # 总工作进程数（格式化）

      jq_running => commify($jq_locked - $jq_stale),  # 实际运行中的作业数
      jq_backlog => commify($jq_backlog),             # 等待队列中的作业数
      jq_done => commify($jq_done),                   # 已完成的作业数
      jq_errored => commify($jq_errored),             # 出错的作业数
      jq_stale => commify($jq_stale),                # 过期的作业数
      jq_total => commify($jq_total),                 # 总作业数

      results => [ jq_log ],  # 作业日志
    }, { layout => undef };
};

true;
