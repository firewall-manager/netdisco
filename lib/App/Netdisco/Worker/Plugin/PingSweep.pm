package App::Netdisco::Worker::Plugin::PingSweep;

# Ping扫描工作器插件
# 提供网络Ping扫描和设备发现功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::JobQueue 'jq_insert';

use Time::HiRes;
use Sys::SigAction 'timeout_call';
use Net::Ping;
use Net::Ping::External;
use Proc::ProcessTable;
use NetAddr::IP qw/:rfc3021 :lower/;

# 注册主阶段工作器
# 执行网络Ping扫描
register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $targets = $job->device
    or return Status->error('missing parameter -d/device with IP prefix');

  # 设置Ping超时时间
  my $timeout = $job->extra || '0.1';

  # 解析网络地址
  my $net = NetAddr::IP->new($targets);
  if (!$net or $net->num == 0 or $net->addr eq '0.0.0.0') {
      return Status->error(
        sprintf 'unable to understand as host, IP, or prefix: %s', $targets)
  }

  # 初始化Ping扫描
  my $job_count = 0;
  my $ping = Net::Ping->new({proto => 'external'});

  # Ping函数
  my $pinger = sub {
    my $host = shift;
    $ping->ping($host);
    debug sprintf 'pinged %s successfully', $host;
  };

  # 允许bash/shell子进程退出
  $SIG{CHLD} = 'IGNORE';
  # debug sprintf 'I am PID %s', $$;

  # 遍历网络地址进行Ping扫描
  ADDRESS: foreach my $idx (0 .. $net->num()) {
    my $addr = $net->nth($idx) or next;
    my $host = $addr->addr;

    # 执行Ping操作
    if (timeout_call($timeout, $pinger, $host)) {
      debug sprintf 'pinged %s and timed out', $host;

      # 清理超时的子进程
      # 这有点粗糙，但需要因为Net::Ping::External不提供任何清理/管理或访问子PID
      my $t = Proc::ProcessTable->new;
      foreach my $p ( @{$t->table} ) {
          if ($p->ppid() and $p->ppid() == $$) {
              my $pid = $p->pid();

              # 杀死子进程的子进程
              foreach my $c ( @{$t->table} ) {
                  if ($c->ppid() and $c->ppid() == $pid) {
                      # debug sprintf 'killing fork %s (%s) of %s', $c->pid(), $c->cmndline(), $p->pid();
                      kill 1, $c->pid();
                  }
              }

              # 杀死子进程
              # debug sprintf 'killing fork %s (%s) of %s', $p->pid(), $p->cmndline(), $$;
              kill 1, $p->pid();
          }
      }

      next ADDRESS;
    }

    # 为响应的主机插入发现任务
    jq_insert([{
      action => 'discover',
      device => $host,
      username => ($ENV{USER} || 'netdisco-do'),
    }]);

    ++$job_count;
  }

  return Status->done(sprintf
    'Finished ping sweep: queued %s jobs from %s hosts', $job_count, $net->num());
});

true;
