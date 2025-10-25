package App::Netdisco::Backend::Role::Scheduler;

# 调度器角色模块
# 提供定时任务调度和作业队列功能

use Dancer qw/:moose :syntax :script/;

use NetAddr::IP;
use JSON::PP ();
use Algorithm::Cron;

use App::Netdisco::Util::MCE;
use App::Netdisco::JobQueue qw/jq_insert/;

use Role::Tiny;
use namespace::clean;

# 工作进程开始
# 初始化调度器，解析定时任务配置
sub worker_begin {
  my $self = shift;
  my $wid  = $self->wid;

  return debug "sch ($wid): no need for scheduler... skip begin" unless setting('schedule');

  debug "entering Scheduler ($wid) worker_begin()";

  foreach my $action (keys %{setting('schedule')}) {
    my $config = setting('schedule')->{$action} or next;

    if (not $config->{when}) {
      error sprintf 'sch (%s): schedule %s is missing time spec', $wid, $action;
      next;
    }

    # 接受单个crontab格式或单独的时间字段
    $config->{when} = Algorithm::Cron->new(
      base => 'local',
      %{(ref {} eq ref $config->{when}) ? $config->{when} : {crontab => $config->{when}}}
    );
  }
}

# 工作进程主体
# 调度器的主要工作循环，检查定时任务并排队作业
sub worker_body {
  my $self = shift;
  my $wid  = $self->wid;

  unless (setting('schedule')) {
    prctl sprintf 'nd2: #%s sched: inactive', $wid;
    return debug "sch ($wid): no need for scheduler... quitting";
  }

  my $coder = JSON::PP->new->utf8(0)->allow_nonref(1)->allow_unknown(1);

  while (1) {

    # 睡眠到下一分钟的某个时间点
    my $naptime = 60 - (time % 60) + int(rand(45));

    prctl sprintf 'nd2: #%s sched: idle', $wid;
    debug "sched ($wid): sleeping for $naptime seconds";

    sleep $naptime;
    prctl sprintf 'nd2: #%s sched: queueing', $wid;

    # 注意：next_time()返回win_start之后的下一时间
    my $win_start = time - (time % 60) - 1;
    my $win_end   = $win_start + 60;

    # 如果有作业到期，将其添加到队列
    foreach my $action (keys %{setting('schedule')}) {
      my $sched       = setting('schedule')->{$action} or next;
      my $real_action = ($sched->{action} || $action);

      # 作业的下一次出现必须在此分钟窗口内
      debug sprintf "sched ($wid): $real_action: win_start: %s, win_end: %s, next: %s", $win_start, $win_end,
        $sched->{when}->next_time($win_start);
      next unless $sched->{when}->next_time($win_start) <= $win_end;

      my @job_specs = ();

      if ($sched->{only} or $sched->{no}) {
        $sched->{label} = $action;
        push @job_specs, {action => 'scheduler', subaction => $coder->encode($sched),};
      }
      else {
        my @hostlist = ();

        foreach my $target (ref $sched->{device} eq ref [] ? @{$sched->{device}} : $sched->{device}) {

          # 健全性检查
          my $net = NetAddr::IP->new($target);
          next if ($target and (!$net or $net->num == 0 or $net->addr eq '0.0.0.0'));

          if (scalar grep { $real_action eq $_ } @{setting('job_targets_prefix')}) {
            push @hostlist, $target;
          }
          else {
            @hostlist = map { (ref $_) ? $_->addr : undef } (defined $target ? ($net->hostenum) : (undef));
          }
        }

        foreach my $host (@hostlist) {
          push @job_specs,
            {action => $real_action, device => $host, port => $sched->{port}, subaction => $sched->{extra},};
        }
      }

      info sprintf 'sched (%s): queueing %s %s jobs', $wid, (scalar @job_specs), $real_action;
      jq_insert(\@job_specs);
    }
  }
}

1;
