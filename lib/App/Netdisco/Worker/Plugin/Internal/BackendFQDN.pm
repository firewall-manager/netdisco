# Netdisco后端FQDN内部插件
# 此模块提供后端主机名解析功能，用于在CLI模式下设置后端主机标识
package App::Netdisco::Worker::Plugin::Internal::BackendFQDN;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Net::Domain 'hostfqdn';
use Scalar::Util 'blessed';

# 注册检查阶段工作器 - 解析后端主机名
register_worker(
  {phase => 'check', driver => 'direct'},    # 检查阶段，直接驱动
  sub {
    my ($job, $workerconf) = @_;
    my $action = $job->action or return;     # 获取作业动作

    # 如果作业在CLI下运行，可能需要BACKEND设置
    return
      unless scalar grep { $_ eq $action } @{setting('deferrable_actions')} and not setting('workers')->{'BACKEND'};

    # 这可能需要几秒钟 - 只执行一次
    info 'resolving backend hostname...';                                  # 解析后端主机名
    setting('workers')->{'BACKEND'} ||= (hostfqdn || 'fqdn-undefined');    # 设置后端标识

    debug sprintf 'Backend identity set to %s', setting('workers')->{'BACKEND'};
  }
);

true;
