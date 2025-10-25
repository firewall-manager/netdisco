package App::Netdisco::Worker::Plugin;

# 工作器插件
# 提供工作器插件的注册和管理功能

use Dancer ':syntax';
use Dancer::Plugin;

use App::Netdisco::Util::Permission qw/acl_matches acl_matches_only/;
use aliased 'App::Netdisco::Worker::Status';

use Term::ANSIColor qw(:constants :constants256);
use Scope::Guard 'guard';
use Storable 'dclone';

# 注册工作器方法
# 注册新的工作器插件
register 'register_worker' => sub {
  my ($self, $first, $second) = plugin_args(@_);

  my $workerconf = (ref $first eq 'HASH' ? $first : {});
  my $code = (ref $first eq 'CODE' ? $first : $second);
  return error "bad param to register_worker"
    unless ((ref sub {} eq ref $code) and (ref {} eq ref $workerconf));

  my $package = (caller)[0];
  ($workerconf->{package} = $package) =~ s/^App::Netdisco::Worker::Plugin:://;
  if ($package =~ m/Plugin::(\w+)(?:::(\w+))?/) {
    $workerconf->{action}    ||= lc($1);
    $workerconf->{namespace} ||= lc($2) if $2;
  }
  return error "failed to parse action in '$package'"
    unless $workerconf->{action};

  # 设置工作器配置默认值
  $workerconf->{title}     ||= '';
  $workerconf->{phase}     ||= 'user';
  $workerconf->{namespace} ||= '_base_';
  $workerconf->{priority}  ||= (exists $workerconf->{driver}
    ? (setting('driver_priority')->{$workerconf->{driver}} || 0) : 0);

  # 创建工作器子程序
  my $worker = sub {
    my $job = shift or die 'missing job param';

    # 输出工作器调试信息
    debug YELLOW, "\N{RIGHTWARDS BLACK ARROW} worker ", GREY10, $workerconf->{package},
      ($workerconf->{pyworklet} ? (' '. $workerconf->{pyworklet}) : ''),
      GREY10, ' p', MAGENTA, $workerconf->{priority},
      ($workerconf->{title} ? (GREY10, ' "', BRIGHT_BLUE, $workerconf->{title}, GREY10, '"') : ''),
      RESET;

    # 检查任务是否已取消
    if ($job->is_cancelled) {
      return $job->add_status( Status->info('skip: job is cancelled') );
    }

    # 检查离线模式下的网络工作器
    if ($job->is_offline
        and $workerconf->{phase} eq 'main'
        and $workerconf->{priority} > 0
        and $workerconf->{priority} < setting('driver_priority')->{'direct'}) {

      return $job->add_status( Status->info('skip: networked worker but job is running offline') );
    }

    # 检查此命名空间是否已在更高优先级通过
    # 并更新任务的命名空间和优先级记录
    return $job->add_status( Status->info('skip: namespace passed at higher priority') )
      if $job->namespace_passed($workerconf);

    # 支持通过action::namespace的部分动作
    if ($job->only_namespace and $workerconf->{phase} ne 'check') {
      # 跳过不是请求的::namespace的命名空间
      if (not ($workerconf->{namespace} eq lc( $job->only_namespace )
        # 除了discover::properties需要运行，所以对于未知设备是early
        # 阶段，但不是::hooks/early（如果实现）
        or (($job->only_namespace ne 'hooks') and ($workerconf->{phase} eq 'early')
             and ($job->device and not $job->device->in_storage)) )) {

        return;
      }
    }

    my @newuserconf = ();
    my @userconf = @{ dclone (setting('device_auth') || []) };

    # 工作器可能是供应商/平台特定的
    if (ref $job->device) {
      my $no   = (exists $workerconf->{no}   ? $workerconf->{no}   : undef);
      my $only = (exists $workerconf->{only} ? $workerconf->{only} : undef);

      return $job->add_status( Status->info('skip: acls restricted') )
        if ($no and acl_matches($job->device, $no))
           or ($only and not acl_matches_only($job->device, $only));

      # 通过驱动器和动作过滤器减少device_auth
      foreach my $stanza (@userconf) {
        next if exists $stanza->{driver} and exists $workerconf->{driver}
          and (($stanza->{driver} || '') ne ($workerconf->{driver} || ''));

        # 在这里过滤而不是在Runner中，因为runner不知道命名空间
        next if exists $stanza->{action}
          and not _find_matchaction($workerconf, lc($stanza->{action}));

        push @newuserconf, dclone $stanza;
      }

      # 每个设备动作但没有设备凭据可用
      return $job->add_status( Status->info('skip: driver or action not applicable') )
        if 0 == scalar @newuserconf
           and $workerconf->{priority} > 0
           and $workerconf->{priority} < setting('driver_priority')->{'direct'};
    }

    # 备份和恢复device_auth
    my $guard = guard { set(device_auth => \@userconf) };
    set(device_auth => \@newuserconf);

    # 运行工作器
    if ($ENV{ND2_WORKER_ROLL_CALL}) {
        return Status->info('-');
    }
    else {
        $code->($job, $workerconf);
    }
  };

  # 存储构建的工作器，Worker.pm稍后将构建调度顺序
  push @{ vars->{'workers'}->{$workerconf->{action}}
              ->{$workerconf->{phase}}
              ->{$workerconf->{namespace}}
              ->{$workerconf->{priority}} }, $worker;
};

# 查找匹配动作方法
# 检查配置是否匹配指定的动作
sub _find_matchaction {
  my ($conf, $action) = @_;
  return true if !defined $action;
  $action = [$action] if ref [] ne ref $action;

  foreach my $f (@$action) {
    return true if
      $f eq $conf->{action} or $f eq "$conf->{action}::$conf->{namespace}";
  }
  return false;
}

register_plugin;
true;

=head1 NAME

App::Netdisco::Worker::Plugin - Netdisco Workers

=head1 Introduction

L<App::Netdisco>'s plugin system allows users to write I<workers> to gather
information from network devices using different I<transports> and store
results in the database.

For example, transports might be SNMP, SSH, or HTTPS. Workers might be
combining those transports with application protocols such as SNMP, NETCONF
(OpenConfig with XML), RESTCONF (OpenConfig with JSON), eAPI, or even CLI
scraping. The combination of transport and protocol is known as a I<driver>.

Workers can be restricted to certain vendor platforms using familiar ACL
syntax. They are also attached to specific actions in Netdisco's backend
operation (discover, macsuck, etc).

See L<https://github.com/netdisco/netdisco/wiki/Backend-Plugins> for details.

=cut

