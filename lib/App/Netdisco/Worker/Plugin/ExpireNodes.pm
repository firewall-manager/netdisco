package App::Netdisco::Worker::Plugin::ExpireNodes;

# 节点过期工作器插件
# 提供节点过期清理功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Dancer::Plugin::DBIC 'schema';

# 注册检查阶段工作器
# 验证节点过期操作的可行性
register_worker({ phase => 'check' }, sub {
  return Status->error('Missing device (-d).')
    unless defined shift->device;
  return Status->done('ExpireNodes is able to run');
});

# 注册主阶段工作器
# 执行节点过期清理操作
register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;

  # 在数据库事务中删除过期节点
  schema('netdisco')->txn_do(sub {
    schema('netdisco')->resultset('Node')->search({
      switch => $job->device->ip,
      ($job->port ? (port => $job->port) : ()),
    })->delete(
      ($job->extra ? () : ({ archive_nodes => 1 }))
    );
  });

  return Status->done('Expired nodes for '. $job->device->ip);
});

true;
