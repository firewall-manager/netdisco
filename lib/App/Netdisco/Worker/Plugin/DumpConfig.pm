package App::Netdisco::Worker::Plugin::DumpConfig;

# 配置转储工作器插件
# 提供系统配置信息转储功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Data::Printer;

# 注册主阶段工作器
# 转储系统配置信息
register_worker(
  {phase => 'main'},
  sub {
    my ($job, $workerconf) = @_;
    my $extra = $job->extra;

    # 获取配置信息
    my $config = config();
    my $dump   = ($extra ? $config->{$extra} : $config);

    # 输出配置信息
    p $dump;
    return Status->done('Dumped config');
  }
);

true;
