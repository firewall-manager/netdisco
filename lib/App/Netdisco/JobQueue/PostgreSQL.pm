package App::Netdisco::JobQueue::PostgreSQL;

# PostgreSQL作业队列模块
# 提供基于PostgreSQL的作业队列管理功能

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::Device 'get_denied_actions';
use App::Netdisco::Backend::Job;
use App::Netdisco::DB::ExplicitLocking ':modes';

use JSON::PP ();
use Try::Tiny;

use base 'Exporter';
our @EXPORT    = ();
our @EXPORT_OK = qw/
  jq_warm_thrusters
  jq_getsome
  jq_locked
  jq_queued
  jq_lock
  jq_defer
  jq_complete
  jq_log
  jq_userlog
  jq_insert
  jq_delete
  /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

# 预热推进器
# 在后端重启时清理和重置设备跳过列表
sub jq_warm_thrusters {
  my $rs = schema(vars->{'tenant'})->resultset('DeviceSkip');

  schema(vars->{'tenant'})->txn_do(sub {
    $rs->search({backend => setting('workers')->{'BACKEND'},}, {for => 'update'},)->update({actionset => []});

    # 在后端重启时，允许所有已达到最大重试次数的设备重试一次
    my $deferrals = setting('workers')->{'max_deferrals'} - 1;
    $rs->search(
      {
        backend   => setting('workers')->{'BACKEND'},
        device    => {'!=' => '255.255.255.255'},
        deferrals => {'>'  => $deferrals},
      },
      {for => 'update'},
    )->update({deferrals => $deferrals});

    $rs->search({
      backend   => setting('workers')->{'BACKEND'},
      actionset => {-value => []},                    # 匹配空数组的特殊语法
      deferrals => 0,
    })->delete;

    # 也清理任何之前的下端提示
    # primeskiplist操作将运行以重新创建它
    $rs->search({
      backend   => setting('workers')->{'BACKEND'},
      device    => '255.255.255.255',
      actionset => {-value => []},                    # 匹配空数组的特殊语法
    })->delete;
  });
}

# 获取一些作业
# 从队列中获取指定数量的作业，处理重复作业和设备权限检查
sub jq_getsome {
  my $num_slots = shift;
  return () unless $num_slots and $num_slots > 0;

  my $jobs     = schema(vars->{'tenant'})->resultset('Admin');
  my @returned = ();

  my $tasty = schema(vars->{'tenant'})->resultset('Virtual::TastyJobs')->search(
    undef, {
      bind => [
        setting('workers')->{'BACKEND'},     setting('job_prio')->{'high'},
        setting('workers')->{'BACKEND'},     setting('workers')->{'max_deferrals'},
        setting('workers')->{'retry_after'}, $num_slots,
      ]
    }
  );

  while (my $job = $tasty->next) {
    if ($job->device and not scalar grep { $job->action eq $_ } @{setting('job_targets_prefix')}) {

      # 需要处理自后端守护进程启动以来发现的设备
      # 并且跳转列表已被初始化。这些应该根据各种ACL进行检查
      # 并在需要时添加device_skip条目，如果应该跳过则返回false
      my @badactions = get_denied_actions($job->device);
      if (scalar @badactions) {
        schema(vars->{'tenant'})->resultset('DeviceSkip')->txn_do_locked(
          EXCLUSIVE,
          sub {
            schema(vars->{'tenant'})
              ->resultset('DeviceSkip')
              ->find_or_create({backend => setting('workers')->{'BACKEND'}, device => $job->device,},
              {key => 'device_skip_pkey'})->add_to_actionset(@badactions);
          }
        );

        # 现在在未来的_getsome()中不会被选中
        next if scalar grep { $_ eq $job->action } @badactions;
      }
    }

    # 移除任何重复的作业，包括如果已有等效作业运行时的此作业

    # 注意作业的自移除有一个无用的日志：它被报告为自身的重复！
    # 但是发生的情况是netdisco已经看到了另一个具有相同参数的运行作业
    # （但查询无法看到该ID以在消息中使用它）

    my %job_properties = (
      action    => $job->action,
      port      => $job->port,
      subaction => $job->subaction,
      -or       => [{device => $job->device}, ($job->device_key ? ({device_key => $job->device_key}) : ()),],

      # 永远不要对用户提交的作业进行去重
      username => {'=' => undef},
      userip   => {'=' => undef},
    );

    my $gone = $jobs->search(
      {
        status => 'queued',
        -and   => [
          %job_properties,
          -or => [
            {job => {'<' => $job->id},},
            {
              job     => $job->id,
              -exists => $jobs->search({
                job     => {'>' => $job->id},
                status  => 'queued',
                backend => {'!=' => undef},
                started => \[q/> (LOCALTIMESTAMP - ?::interval)/, setting('jobs_stale_after')],
                %job_properties,
              })->as_query,
            }
          ],
        ],
      },
      {for => 'update'}
    )->update({status => 'info', log => (sprintf 'duplicate of %s', $job->id)});

    debug sprintf 'getsome: cancelled %s duplicate(s) of job %s', ($gone || 0), $job->id;
    push @returned, App::Netdisco::Backend::Job->new({$job->get_columns});
  }

  return @returned;
}

# 获取锁定的作业
# 返回当前后端锁定的作业列表
sub jq_locked {
  my @returned = ();
  my $rs       = schema(vars->{'tenant'})->resultset('Admin')->search({
    status  => 'queued',
    backend => setting('workers')->{'BACKEND'},
    started => \[q/> (LOCALTIMESTAMP - ?::interval)/, setting('jobs_stale_after')],
  });

  while (my $job = $rs->next) {
    push @returned, App::Netdisco::Backend::Job->new({$job->get_columns});
  }
  return @returned;
}

# 获取排队的作业
# 返回指定类型作业的设备列表
sub jq_queued {
  my $job_type = shift;

  return schema(vars->{'tenant'})
    ->resultset('Admin')
    ->search({device => {'!=' => undef}, action => $job_type, status => 'queued',})
    ->get_column('device')
    ->all;
}

# 锁定作业
# 锁定数据库行并更新以显示作业已被选取
sub jq_lock {
  my $job = shift;
  return true unless $job->id;
  my $happy = false;

  # 锁定数据库行并更新以显示作业已被选取
  try {
    my $updated
      = schema(vars->{'tenant'})
      ->resultset('Admin')
      ->search({job => $job->id, status => 'queued'}, {for => 'update'})
      ->update({status => 'queued', backend => setting('workers')->{'BACKEND'}, started => \"LOCALTIMESTAMP",});

    $happy = true if $updated > 0;
  }
  catch {
    error $_;
  };

  return $happy;
}

# 延迟作业
# 将作业标记为延迟，增加设备的延迟计数
sub jq_defer {
  my $job   = shift;
  my $happy = false;

  # 注意这会污染设备上的所有操作。例如，如果macsuck和arpnip都被允许，
  # 但macsuck失败10次，那么arpnip（以及所有其他操作）将在设备上被阻止

  # 考虑到延迟仅由SNMP连接失败触发，这种行为似乎是合理的（或者可能是可取的）

  # deferrable_actions设置作为此行为的变通方法存在
  # 如果任何操作需要（即每个设备的操作但不增加延迟计数并简单地重试）

  try {
    schema(vars->{'tenant'})->resultset('DeviceSkip')->txn_do_locked(
      EXCLUSIVE,
      sub {
        if ($job->device and not scalar grep { $job->action eq $_ } @{setting('deferrable_actions') || []}) {

          schema(vars->{'tenant'})
            ->resultset('DeviceSkip')
            ->find_or_create({backend => setting('workers')->{'BACKEND'}, device => $job->device,},
            {key => 'device_skip_pkey'})->increment_deferrals;
        }

        debug sprintf 'defer: job %s', ($job->id || 'unknown');

        # 锁定数据库行并更新以显示作业可用
        schema(vars->{'tenant'})->resultset('Admin')->search({job => $job->id}, {for => 'update'})->update({
          device  => $job->device,    # 如果作业有别名，这将设置为规范形式
          status  => 'queued',
          backend => undef,
          started => undef,
          log     => $job->log,
        });
      }
    );
    $happy = true;
  }
  catch {
    error $_;
  };

  return $happy;
}

# 完成作业
# 锁定数据库行并更新以显示作业已完成/错误
sub jq_complete {
  my $job   = shift;
  my $happy = false;

  # 锁定数据库行并更新以显示作业已完成/错误

  # 现在SNMP连接失败是延迟而不是错误，任何完成状态，
  # 无论成功还是失败，都表示SNMP连接。重置连接失败计数器以忘记偶尔的连接故障

  try {
    schema(vars->{'tenant'})->resultset('DeviceSkip')->txn_do_locked(
      EXCLUSIVE,
      sub {
        if (  $job->device
          and not $job->is_offline
          and not scalar grep { $job->action eq $_ } @{setting('job_targets_prefix')}) {

          schema(vars->{'tenant'})
            ->resultset('DeviceSkip')
            ->find_or_create({backend => setting('workers')->{'BACKEND'}, device => $job->device,},
            {key => 'device_skip_pkey'})->update({deferrals => 0});
        }

        schema(vars->{'tenant'})->resultset('Admin')->search({job => $job->id}, {for => 'update'})->update({
          status   => $job->status,
          log      => (ref($job->log) eq ref('')) ? $job->log : '',
          started  => $job->started,
          finished => $job->finished,
          (($job->action eq 'hook') ? (subaction => $job->subaction)                              : ()),
          ($job->only_namespace     ? (action    => ($job->action . '::' . $job->only_namespace)) : ()),
        });
      }
    );
    $happy = true;
  }
  catch {
    # use DDP; p $job;
    error $_;
  };

  return $happy;
}

# 获取作业日志
# 根据各种参数搜索和过滤作业日志
sub jq_log {
  return schema(vars->{'tenant'})->resultset('Admin')->search(
    {
      (param('backend')  ? ('me.backend' => param('backend'))                                              : ()),
      (param('action')   ? ('me.action'  => param('action'))                                               : ()),
      (param('device')   ? (-or => [{'me.device' => param('device')}, {'target.ip' => param('device')},],) : ()),
      (param('username') ? ('me.username' => param('username'))                                            : ()),
      (
        param('status')
        ? ((param('status') eq 'Running')
          ? (-and => [{'me.backend' => {'!=' => undef}}, {'me.status' => 'queued'},],)
          : ('me.status' => lc(param('status'))))
        : ()
      ),
      (
        param('duration')
        ? (
          -bool => [
            -or => [
              {
                'me.finished' => undef,
                'me.started'  => {'<' => \[q{(CURRENT_TIMESTAMP - ? ::interval)}, param('duration') . ' minutes']},
              },
              -and => [
                {'me.started'  => {'!=' => undef}},
                {'me.finished' => {'!=' => undef}},
                \[q{ (me.finished - me.started) > ? ::interval }, param('duration') . ' minutes'],
              ],
            ],
          ],
          )
        : ()
      ),
      'me.log' => [{'=' => undef}, {'-not_like' => 'duplicate of %'},],
    },
    {prefetch => 'target', order_by => {-desc => [qw/entered device action/]}, rows => (setting('jobs_qdepth') || 50),}
  )->with_times->hri->all;
}

# 获取用户日志
# 返回指定用户的作业日志
sub jq_userlog {
  my $user = shift;
  return schema(vars->{'tenant'})->resultset('Admin')->search({
    username => $user,
    log      => {'-not_like' => 'duplicate of %'},
    finished => {'>'         => \"(CURRENT_TIMESTAMP - interval '5 seconds')"},
  })->with_times->all;
}

# 插入作业
# 将作业插入到队列中，支持内联操作和自定义字段更新
sub jq_insert {
  my $jobs = shift;
  $jobs = [$jobs] if ref [] ne ref $jobs;

  my $happy = false;
  try {
    schema(vars->{'tenant'})->txn_do(sub {
      if (  scalar @$jobs == 1
        and defined $jobs->[0]->{device}
        and scalar grep { $_ eq $jobs->[0]->{action} } @{setting('_inline_actions') || []}) {

        # 对于heroku托管来说有点hack，以避免数据库过载
        return true if setting('defanged_admin') ne 'admin';

        my $spec = $jobs->[0];
        my $row  = undef;

        if ($spec->{port}) {
          $row = schema(vars->{'tenant'})->resultset('DevicePort')->find($spec->{port}, $spec->{device});
          undef $row
            unless scalar grep { ('cf_' . $_) eq $spec->{action} }
            grep {defined} map { $_->{name} } @{setting('custom_fields')->{device_port} || []};
        }
        else {
          $row = schema(vars->{'tenant'})->resultset('Device')->find($spec->{device});
          undef $row
            unless scalar grep { ('cf_' . $_) eq $spec->{action} }
            grep {defined} map { $_->{name} } @{setting('custom_fields')->{device} || []};
        }

        die 'failed to find row for custom field update' unless $row;

        my $coder = JSON::PP->new->utf8(0)->allow_nonref(1)->allow_unknown(1);
        $spec->{subaction} = $coder->encode($spec->{extra} || $spec->{subaction});
        $spec->{action} =~ s/^cf_//;
        $row->make_column_dirty('custom_fields');
        $row->update({
          custom_fields => \['jsonb_set(custom_fields, ?, ?)' => (qq{{$spec->{action}}}, $spec->{subaction})]
        })->discard_changes();
      }
      else {
        schema(vars->{'tenant'})->resultset('Admin')->populate([
          map { {
            device     => $_->{device},
            device_key => $_->{device_key},
            port       => $_->{port},
            action     => $_->{action},
            subaction  => ($_->{extra} || $_->{subaction}),
            username   => $_->{username},
            userip     => $_->{userip},
            status     => 'queued',
          } } @$jobs
        ]);
      }
    });
    $happy = true;
  }
  catch {
    error $_;
  };

  return $happy;
}

# 删除作业
# 删除指定的作业或所有非primeskiplist作业
sub jq_delete {
  my $id = shift;

  if ($id) {
    schema(vars->{'tenant'})->txn_do(sub {
      schema(vars->{'tenant'})->resultset('Admin')->search({job => $id})->delete;
    });
  }
  else {
    schema(vars->{'tenant'})->txn_do(sub {
      schema(vars->{'tenant'})->resultset('Admin')->search({action => {'!=' => 'primeskiplist'}})->delete();
    });
  }
}

true;
