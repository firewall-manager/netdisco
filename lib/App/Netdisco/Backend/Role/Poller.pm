package App::Netdisco::Backend::Role::Poller;

# 轮询器角色模块
# 提供作业执行和轮询功能

use Dancer qw/:moose :syntax :script/;

use Try::Tiny;
use App::Netdisco::Util::MCE;

use Time::HiRes 'sleep';
use App::Netdisco::JobQueue qw/jq_defer jq_complete/;

use Role::Tiny;
use namespace::clean;

# 为轮询器任务添加分发方法
with 'App::Netdisco::Worker::Runner';

# 工作进程开始
# 记录工作进程启动时间
sub worker_begin { (shift)->{started} = time }

# 工作进程主体
# 轮询器的主要工作循环，从队列获取作业并执行
sub worker_body {
  my $self = shift;
  my $wid  = $self->wid;

  while (1) {
    prctl sprintf 'nd2: #%s poll: idle', $wid;

    my $job = $self->{queue}->dequeue(1);
    next unless defined $job;

    try {
      $job->started(scalar localtime);
      prctl sprintf 'nd2: #%s poll: #%s: %s', $wid, $job->id, $job->display_name;
      info sprintf "pol (%s): starting %s job(%s) at %s", $wid, $job->action, $job->id, $job->started;
      $self->run($job);
    }
    catch {
      $job->status('error');
      $job->log("error running job: $_");
      $self->sendto('stderr', $job->log . "\n");
    };

    $self->close_job($job);
    sleep(setting('workers')->{'min_runtime'} || 0);
    $self->exit(0);    # 回收工作进程
  }
}

# 关闭作业
# 完成作业处理，根据状态决定是延迟还是完成
sub close_job {
  my ($self, $job) = @_;
  my $now = scalar localtime;

  info sprintf "pol (%s): wrapping up %s job(%s) - status %s at %s", $self->wid, $job->action, $job->id, $job->status,
    $now;

  try {
    if ($job->status eq 'defer') {
      jq_defer($job);
    }
    else {
      $job->finished($now);
      jq_complete($job);
    }
  }
  catch { $self->sendto('stderr', "error closing job: $_\n") };
}

1;
