package App::Netdisco::Transport::Python;

# 导入 Dancer 框架
use Dancer qw/:syntax :script/;

# 导入单例基类和状态模块
use base 'Dancer::Object::Singleton';
use aliased 'App::Netdisco::Worker::Status';
use App::Netdisco::Util::Python 'py_cmd';

# 导入进程管理、编码、文件处理和数据处理模块
use IPC::Run 'harness';
use MIME::Base64 'decode_base64';
use Path::Class;
use File::ShareDir 'dist_dir';
use File::Slurper qw/read_text write_text/;
use File::Temp    ();
use JSON::PP      ();
use YAML::XS      ();
use Try::Tiny;

=head1 NAME

App::Netdisco::Transport::Python

=head1 DESCRIPTION

Not really a transport, but has similar behaviour to a Transport.

Returns an object which has a live Python subprocess expecting
instruction to run worklets.

 my $runsub = App::Netdisco::Transport::Python->py_worklet();

=cut

# 定义包属性
__PACKAGE__->attributes(qw/ runner stdin stdout context /);

# 初始化方法
# 用途：初始化 Python 传输对象，创建持久的 Python 子进程
sub init {
  my ($class, $instance) = @_;

  # 创建标准输入输出句柄
  my ($stdin, $stdout);
  $instance->stdin(\$stdin);
  $instance->stdout(\$stdout);
  $instance->context(File::Temp->new());

  # 构建 Python 命令
  my $cmd = [py_cmd('run_worklet'), $instance->context->filename];
  debug "\N{SNAKE} starting persistent Python worklet subprocess";

  # 创建进程管理器
  $instance->runner(harness(
    ($ENV{ND2_PYTHON_HARNESS_DEBUG} ? (debug => 1) : ()),
    $cmd, '<', \$stdin, '1>', \$stdout, '2>', sub { debug $_[0] },
  ));

  debug $instance->context if $ENV{ND2_PYTHON_HARNESS_DEBUG};
  return $instance;
}

=head1 py_worklet( )

Contacts a live Python worklet runner to run a job and retrieve output.

=cut

# Python 工作单元执行
# 用途：联系活动的 Python 工作单元运行器来运行作业并检索输出
sub py_worklet {
  my ($self, $job, $workerconf) = @_;
  my $action = $workerconf->{action};

  # 创建 JSON 编码器
  my $coder = JSON::PP->new->utf8(1)->allow_nonref(1)->allow_unknown(1)->allow_blessed(1)->allow_bignum(1);

  # 这仅在第一次使用时真正使用（pump 调用 start）
  $ENV{'ND2_JOB_METADATA'}  = $coder->encode({%$job, device => (($job->device || '') . '')});
  $ENV{'ND2_CONFIGURATION'} = $coder->encode(config());
  $ENV{'ND2_FSM_TEMPLATES'}
    = Path::Class::Dir->new(dist_dir('App-Netdisco'))->subdir('python')->subdir('tfsm')->stringify;

  my $inref  = $self->stdin;
  my $outref = $self->stdout;

  # 将最新的变量复制到工作单元
  write_text($self->context->filename, $coder->encode({vars => vars()}));

  # 在运行之前是必要的，但首先执行（而不是之后）以帮助调试
  $$outref = '';

  # 发送工作单元命令并等待响应
  $$inref = $workerconf->{pyworklet} . "\n";
  $self->runner->pump until ($$outref and $$outref =~ /^\.\Z/m);

  # 读取上下文数据并清理
  my $context = read_text($self->context->filename);
  truncate($self->context, 0);    # 不要在磁盘上留下东西

  # 解码返回数据
  my $retdata = try { YAML::XS::Load(decode_base64($context)) };    # 可能会爆炸
  $retdata = {} if not ref $retdata or 'HASH' ne ref $retdata;

  # 处理返回状态和日志
  my $status = $retdata->{status} || '';
  my $log    = $retdata->{log}
    || ($status eq 'done' ? (sprintf '%s exit OK', $action) : (sprintf '%s exit with status "%s"', $action, $status));

  # 设置变量和状态
  var($_          => $retdata->{stash}->{$_}) for keys %{$retdata->{stash} || {}};
  var(live_python => true);

  return ($status ? Status->$status($log) : Status->info('worklet returned no status'));
}

true;
