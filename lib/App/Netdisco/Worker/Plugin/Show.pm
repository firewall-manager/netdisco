package App::Netdisco::Worker::Plugin::Show;

# 信息显示工作器插件
# 提供SNMP信息显示功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use JSON::PP ();
use Data::Printer ();
use App::Netdisco::Transport::SNMP;

# 注册检查阶段工作器
# 验证信息显示操作的可行性
register_worker({ phase => 'check' }, sub {
  # 检查设备参数
  return Status->error('Missing device (-d).')
    unless defined shift->device;
  return Status->done('Show is able to run');
});

# 注册主阶段工作器
# 执行SNMP信息显示操作
register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $class, $object) = map {$job->$_} qw/device port extra/;

  # 设置SNMP类名
  $class = 'SNMP::Info::'.$class if $class and $class !~ m/^SNMP::Info::/;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device, $class);

  # 设置对象名称和MIB模块
  $object ||= 'interfaces';
  my $orig_object = $object;
  my ($mib, $leaf) = split m/::/, $object;
  SNMP::loadModules($mib) if $mib and $leaf and $mib ne $leaf;
  $object =~ s/[-:]/_/g;

  # 获取SNMP信息
  my $result = sub { eval { $snmp->$object() } };

  # 根据环境变量选择输出格式
  if ($ENV{ND2_DO_QUIET}) {
      # 使用JSON格式输出
      my $coder = JSON::PP->new->utf8(1)
                               ->allow_nonref(1)
                               ->allow_unknown(1)
                               ->allow_blessed(1)
                               ->allow_bignum(1);
      print $coder->encode( $result->() );
  }
  else {
      # 使用Data::Printer格式输出
      Data::Printer::p( $result->() );
  }

  return Status->done(
    sprintf "Showed %s response from %s", $orig_object, $device->ip);
});

true;
