# Netdisco删除钩子插件
# 此模块提供删除操作完成后的钩子功能，用于在设备删除任务完成后执行自定义操作
package App::Netdisco::Worker::Plugin::Delete::Hooks;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Worker;
use App::Netdisco::Util::Permission qw/acl_matches acl_matches_only/;

# 注册后期阶段工作器 - 在删除任务完成后执行钩子
register_worker(
  {phase => 'late'},    # 后期阶段工作器
  sub {
    my ($job, $workerconf) = @_;
    my $count = 0;      # 钩子执行计数器

    # 检查任务状态，只有成功完成的任务才执行钩子
    my $best = $job->best_status;
    if (Status->$best->level != Status->done->level) {
      return Status->info(sprintf ' [%s] hooks - skipping due to incomplete job', $job->device);
    }

    # 遍历配置的钩子
    foreach my $conf (@{setting('hooks')}) {
      my $no   = ($conf->{'filter'}->{'no'}   || []);    # 排除过滤器
      my $only = ($conf->{'filter'}->{'only'} || []);    # 仅包含过滤器

      # 检查设备是否匹配排除条件
      next if acl_matches($job->device, $no);

      # 检查设备是否匹配仅包含条件
      next unless acl_matches_only($job->device, $only);

      # 如果是删除事件，执行钩子
      if ($conf->{'event'} eq 'delete') {
        $count += queue_hook('delete', $conf);    # 排队执行删除钩子
        debug sprintf ' [%s] hooks - %s queued', 'delete', $job->device;
      }
    }

    return Status->info(sprintf ' [%s] hooks - %d queued', $job->device, $count);
  }
);

true;
