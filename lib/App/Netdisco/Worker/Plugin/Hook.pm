package App::Netdisco::Worker::Plugin::Hook;

# 钩子工作器插件
# 提供钩子功能执行支持

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

# 注册检查阶段工作器
# 验证钩子功能执行的可行性
register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;

  # 检查是否只能运行特定钩子
  return Status->error('can only run a specific hook')
    unless $job->action eq 'hook' and defined $job->only_namespace;

  return Status->done('Hook is able to run.');
});

true;
