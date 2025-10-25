package App::Netdisco::Worker::Plugin::GetAPIKey;

# API密钥获取工作器插件
# 提供用户API密钥生成和管理功能

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

# 注册检查阶段工作器
# 验证API密钥获取操作的可行性
register_worker(
  {phase => 'check'},
  sub {
    return Status->error('Missing user (-e).') unless shift->extra;
    return Status->done('GetAPIKey is able to run');
  }
);

# 注册主阶段工作器
# 生成或更新用户API密钥
register_worker(
  {phase => 'main'},
  sub {
    my ($job, $workerconf) = @_;
    my $username = $job->extra;

    # 查找用户记录
    my $user = schema('netdisco')->resultset('User')->find({username => $username});

    # 检查用户是否存在
    return Status->error("No such user") unless $user and $user->in_storage;

    # 从Dancer::Plugin::Auth::Extensible内部获取认证提供者
    my $provider = Dancer::Plugin::Auth::Extensible::auth_provider('users');

    # 如果有当前有效令牌则重新颁发并重置计时器
    $user->update({
      token_from => time, ($provider->validate_api_token($user->token) ? () : (token => \'md5(random()::text)')),
    })->discard_changes();

    return Status->done(sprintf 'Set token for user %s: %s', $username, $user->token);
  }
);

true;
