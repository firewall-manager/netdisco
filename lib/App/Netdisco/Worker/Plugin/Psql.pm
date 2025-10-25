package App::Netdisco::Worker::Plugin::Psql;

# PostgreSQL交互工作器插件
# 提供PostgreSQL数据库交互功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

# 注册主阶段工作器
# 执行PostgreSQL数据库交互
register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $extra = $job->extra;

  # 执行PostgreSQL命令
  if ($extra) {
      # 执行指定的SQL命令
      system('psql', '-c', $extra);
  }
  else {
      # 启动交互式PostgreSQL会话
      system('psql');
  }

  return Status->done('psql session closed.');
});

true;
