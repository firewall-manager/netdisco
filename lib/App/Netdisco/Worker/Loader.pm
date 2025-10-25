package App::Netdisco::Worker::Loader;

# 工作器加载器
# 提供工作器插件的加载和管理功能

use strict;
use warnings;

use Module::Load ();
use Dancer qw/:moose :syntax/;

use Moo::Role;
use namespace::clean;

# 定义工作器属性
# 包含各个阶段的工作器集合和传输要求标志
has [qw/workers_check
        workers_early
        workers_main
        workers_user
        workers_store
        workers_late
        transport_required/] => ( is => 'rw' );

# 加载工作器方法
# 根据动作加载相应的工作器插件
sub load_workers {
  my $self = shift;
  my $action = $self->job->action or die "missing action\n";

  my @core_plugins = @{ setting('worker_plugins') || [] };
  my @user_plugins = @{ setting('extra_worker_plugins') || [] };

  # 为当前动作加载工作器插件
  foreach my $plugin (@user_plugins, @core_plugins) {
    $plugin =~ s/^X::/+App::NetdiscoX::Worker::Plugin::/;
    $plugin = 'App::Netdisco::Worker::Plugin::'. $plugin
      if $plugin !~ m/^\+/;
    $plugin =~ s/^\+//;

    next unless $plugin =~ m/::Plugin::(?:${action}|Internal)(?:::|$)/i;
    $ENV{ND2_LOG_PLUGINS} && debug "loading worker plugin $plugin";
    Module::Load::load $plugin;
  }

  # 同时加载配置的Python工作器填充程序
  if (setting('enable_python_worklets')) {
      # 通过将动作名称传递给import()来实现
      Module::Load::load 'App::Netdisco::Worker::Plugin::PythonShim', $action;
  }

  my $workers = vars->{'workers'}->{$action} || {};

  # 需要合并内部工作器而不覆盖动作工作器
  # 我们还删除任何"阶段"（子命名空间）并安装到"__internal__"
  # 其运行优先级高于"_base_"和任何其他

  foreach my $phase (qw/check early main user store late/) {
    next if exists $workers->{$phase}->{'__internal__'};

    next unless exists vars->{'workers'}->{'internal'}
      and exists vars->{'workers'}->{'internal'}->{$phase};
    my $internal = vars->{'workers'}->{'internal'};

    # 内部工作器的命名空间实际上是工作器名称，因此必须
    # 排序以"保留"插件加载顺序
    foreach my $namespace (sort keys %{ $internal->{$phase} }) {
      foreach my $priority (keys %{ $internal->{$phase}->{$namespace} }) {
        push @{ $workers->{$phase}->{'__internal__'}->{$priority} },
          @{ $internal->{$phase}->{$namespace}->{$priority} };
      }
    }
  }

  # 现在vars->{workers}已填充，我们设置调度顺序
  my $driverless_main = 0;

  foreach my $phase (qw/check early main user store late/) {
    my $pname = "workers_${phase}";
    my @wset = ();

    foreach my $namespace (sort keys %{ $workers->{$phase} }) {
      foreach my $priority (sort {$b <=> $a}
                            keys %{ $workers->{$phase}->{$namespace} }) {

        ++$driverless_main if $phase eq 'main'
          and ($priority == 0 or $priority == setting('driver_priority')->{'direct'});
        push @wset, @{ $workers->{$phase}->{$namespace}->{$priority} };
      }
    }

    $self->$pname( \@wset );
  }

  # 设置传输要求标志
  $self->transport_required( $driverless_main ? false : true );
}

true;
