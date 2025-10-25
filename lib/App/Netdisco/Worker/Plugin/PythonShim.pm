package App::Netdisco::Worker::Plugin::PythonShim;

# Python工作器桥接插件
# 提供Python工作器插件动态加载和注册功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;

use App::Netdisco::Transport::Python ();

# 导入函数
# 动态加载Python工作器插件
sub import {
  my ($pkg, $action) = @_;
  return unless $action;

  # 查找Python工作器插件
  _find_python_worklets($action, $_) for qw/python_worker_plugins extra_python_worker_plugins/;
}

# 查找Python工作器插件函数
# 解析配置并注册Python工作器
sub _find_python_worklets {
  my ($action, $setting) = @_;
  my $config = setting($setting);
  return unless $config and ref [] eq ref $config;

  # 遍历配置条目
  foreach my $entry (@{$config}) {
    my $worklet = undef;

    # 处理字典和字符串配置
    if (ref {} eq ref $entry) {
      $worklet = (keys %$entry)[0];
    }
    else {
      $worklet = $entry;
    }
    next unless $worklet and $worklet =~ m/^${action}\./;
    my @parts = split /\./, $worklet;

    # 构建基础配置
    my %base = (
      action    => shift @parts,
      pyworklet => ($setting =~ m/extra/ ? setting('extra_python_worker_package_namespace') : 'netdisco')
    );
    my %phases = (map { $_ => '' } qw(check early main user store late));

    # 解析阶段信息
    while (my $phase = shift @parts) {
      if (exists $phases{$phase}) {
        $base{phase} = $phase;
        last;
      }
      else {
        push @{$base{namespace}}, $phase;
      }
    }

    # 解析驱动信息
    if (scalar @parts and exists setting('driver_priority')->{$parts[0]}) {
      $base{driver} = shift @parts;
    }

    # 解析平台信息
    $base{platform} = [@parts] if scalar @parts;

    # 注册Python工作器
    if (ref {} eq ref $entry) {
      my $rhs = (values %$entry)[0];
      if (ref [] eq ref $rhs) {

        # 处理多个驱动
        foreach my $driver (@{$rhs}) {
          _register_python_worklet({%base, driver => $driver});
        }
      }
      else {
        # 处理单个驱动配置
        _register_python_worklet({%base, %$rhs});
      }
    }
    else {
      # 处理简单配置
      _register_python_worklet({%base});
    }
  }
}

# 注册Python工作器函数
# 注册Python工作器到工作器系统
sub _register_python_worklet {
  my $workerconf = shift;

  # 构建Python工作器名称
  $workerconf->{pyworklet} .= _build_pyworklet(%$workerconf);

  # 处理命名空间
  $workerconf->{full_namespace} = join '::', @{$workerconf->{namespace}} if exists $workerconf->{namespace};
  $workerconf->{namespace}      = $workerconf->{namespace}->[0] if exists $workerconf->{namespace};

  # 调试日志
  $ENV{ND2_LOG_PLUGINS} && debug sprintf 'loading python worklet a:%s s:%s p:%s d:%s/p:%s',
    (exists $workerconf->{action}    ? ($workerconf->{action}    || '?') : '-'),
    (exists $workerconf->{namespace} ? ($workerconf->{namespace} || '?') : '-'),
    (exists $workerconf->{phase}     ? ($workerconf->{phase}     || '?') : '-'),
    (exists $workerconf->{driver}    ? ($workerconf->{driver}    || '?') : '-'),
    (exists $workerconf->{priority}  ? ($workerconf->{priority}  || '?') : '-');

  # 注册工作器
  register_worker($workerconf, sub { App::Netdisco::Transport::Python->py_worklet(@_) });
}

# 构建Python工作器名称函数
# 构建Python工作器的完整名称
sub _build_pyworklet {
  my %base = @_;
  return join '.', '', 'worklet', $base{action}, (exists $base{namespace} ? @{$base{namespace}} : ()), $base{phase},
    (exists $base{driver} ? $base{driver} : ()), (exists $base{platform} ? @{$base{platform}} : ());
}

true;
