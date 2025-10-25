package App::Netdisco::Worker::Plugin::TastyJobs;

# 作业显示工作器插件
# 提供作业队列信息显示功能

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Data::Printer ();
use App::Netdisco::JobQueue 'jq_getsome';

# 注册主阶段工作器
# 显示作业队列信息
register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  # 获取要显示的作业数量
  my $num_slots = ($job->extra || 20);

  # 使用事务保护获取作业
  my $txn_guard = schema('netdisco')->storage->txn_scope_guard;
  my @jobs = map {  { %{ $_ } } } jq_getsome($num_slots);
  undef $txn_guard;

  # 使用Data::Printer显示作业信息
  Data::Printer::p( @jobs );

  return Status->done("Showed the tastiest jobs");
});

true;
