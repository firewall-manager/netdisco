package App::Netdisco::Transport::SSH;

# 导入 Dancer 框架
use Dancer qw/:syntax :script/;

# 导入设备、模块加载、SSH 连接和异常处理模块
use App::Netdisco::Util::Device 'get_device';
use Module::Load ();
use Net::OpenSSH;
use Try::Tiny;

# 导入单例基类
use base 'Dancer::Object::Singleton';

=head1 NAME

App::Netdisco::Transport::SSH

=head1 DESCRIPTION

Returns an object which has an active SSH connection which can be used
for some actions such as arpnip.

 my $cli = App::Netdisco::Transport::SSH->session_for( ... );

=cut

# 定义包属性
__PACKAGE__->attributes(qw/ sessions /);

# 初始化方法
# 用途：初始化 SSH 传输对象，设置信号处理并创建会话缓存
sub init {
  my ($class, $self) = @_;
  $SIG{CHLD} = 'IGNORE';
  $self->sessions({});
  return $self;
}

=head1 session_for( $ip )

Given an IP address, returns an object instance configured for and connected
to that device.

Returns C<undef> if the connection fails.

=cut

# 内部会话类
{
  package MySession;
  use Moo;

  # 定义会话属性
  has 'ssh'      => (is => 'rw');
  has 'auth'     => (is => 'rw');
  has 'host'     => (is => 'rw');
  has 'platform' => (is => 'rw');

  # ARP 和 IP 地址查询方法
  sub arpnip {
    my $self = shift;
    $self->platform->arpnip(@_, $self->host, $self->ssh, $self->auth) if $self->platform->can('arpnip');
  }

  # MAC 地址收集方法
  sub macsuck {
    my $self = shift;
    $self->platform->macsuck(@_, $self->host, $self->ssh, $self->auth) if $self->platform->can('macsuck');
  }

  # 子网查询方法
  sub subnets {
    my $self = shift;
    $self->platform->subnets(@_, $self->host, $self->ssh, $self->auth) if $self->platform->can('subnets');
  }
}

# 获取会话连接
# 用途：根据 IP 地址返回配置并连接到该设备的对象实例
sub session_for {
  my ($class, $ip) = @_;

  my $device   = get_device($ip)            or return undef;
  my $sessions = $class->instance->sessions or return undef;

  # 检查缓存
  return $sessions->{$device->ip} if exists $sessions->{$device->ip};
  debug sprintf 'cli session cache warm: [%s]', $device->ip;

  # 获取认证配置
  my $auth = (setting('device_auth') || []);
  if (1 != scalar @$auth) {
    error sprintf " [%s] require only one matching auth stanza", $device->ip;
    return undef;
  }
  $auth = $auth->[0];

  # 检查平台配置
  if (!defined $auth->{platform}) {
    error sprintf " [%s] Perl SSH platform not specified, assuming Python", $device->ip;
    return undef;
  }

  # 配置 SSH 主选项
  my @master_opts = qw(-o BatchMode=no);
  push(@master_opts, @{$auth->{ssh_master_opts}}) if $auth->{ssh_master_opts};

  # 创建 SSH 连接
  $Net::OpenSSH::debug = $ENV{SSH_TRACE};
  my $ssh = Net::OpenSSH->new(
    $device->ip,
    user                => $auth->{username},
    password            => $auth->{password},
    key_path            => $auth->{key_path},
    passphrase          => $auth->{passphrase},
    port                => $auth->{port},
    batch_mode          => $auth->{batch_mode},
    timeout             => $auth->{timeout} ? $auth->{timeout} : 30,
    async               => 0,
    default_stderr_file => '/dev/null',
    master_opts         => \@master_opts
  );

  # 检查连接错误
  if ($ssh->error) {
    error sprintf " [%s] ssh connection error [%s]", $device->ip, $ssh->error;
    return undef;
  }
  elsif (!$ssh) {
    error sprintf " [%s] Net::OpenSSH instantiation error", $device->ip;
    return undef;
  }

  # 加载平台模块
  my $platform = "App::Netdisco::SSHCollector::Platform::" . $auth->{platform};
  my $happy    = false;
  try {
    Module::Load::load $platform;
    $happy = true;
  }
  catch { error $_ };
  return unless $happy;

  # 创建会话对象
  my $sess = MySession->new(ssh => $ssh, auth => $auth, host => $device->ip, platform => $platform->new(),);

  return ($sessions->{$device->ip} = $sess);
}

true;
