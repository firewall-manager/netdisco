use utf8;
package App::Netdisco::DB::Result::Admin;

# 管理员任务结果类
# 提供管理员任务和作业的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("admin");

# 定义表列
# 包含任务的所有信息：ID、时间、设备、动作、状态等
__PACKAGE__->add_columns(
  "job",
  {data_type => "integer", is_auto_increment => 1, is_nullable => 0, sequence => "admin_job_seq",},
  "entered", {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => {default_value => \"LOCALTIMESTAMP"},
  },
  "started",
  {data_type => "timestamp", is_nullable => 1},
  "finished",
  {data_type => "timestamp", is_nullable => 1},
  "device",
  {data_type => "inet", is_nullable => 1},
  "port",
  {data_type => "text", is_nullable => 1},
  "action",
  {data_type => "text", is_nullable => 1},
  "subaction",
  {data_type => "text", is_nullable => 1},
  "status",
  {data_type => "text", is_nullable => 1},
  "username",
  {data_type => "text", is_nullable => 1},
  "userip",
  {data_type => "inet", is_nullable => 1},
  "log",
  {data_type => "text", is_nullable => 1},
  "debug",
  {data_type => "boolean", is_nullable => 1},
  "device_key",
  {data_type => "text", is_nullable => 1},
  "backend",
  {data_type => "text", is_nullable => 1},
);

# 设置主键
__PACKAGE__->set_primary_key("job");

=head1 RELATIONSHIPS

=head2 device_skips( $backend?, $max_deferrals?, $retry_after? )

Returns the set of C<device_skip> entries which apply to this job. They match
the device IP, current backend, and job action.

You probably want to use the ResultSet method C<skipped> which completes this
query with a C<backend> host, C<max_deferrals>, and C<retry_after> parameters
(or sensible defaults).

=cut

# 定义关联关系：设备跳过
# 返回适用于此任务的设备跳过条目集合
__PACKAGE__->might_have(
  device_skips => 'App::Netdisco::DB::Result::DeviceSkip',
  sub {
    my $args = shift;
    return {
      "$args->{foreign_alias}.backend" => {'='    => \'?'},
      "$args->{foreign_alias}.device"  => {-ident => "$args->{self_alias}.device"},
      -or                              => [
        "$args->{foreign_alias}.actionset" => {'@>' => \"string_to_array($args->{self_alias}.action,'')"},
        -and                               => [
          "$args->{foreign_alias}.deferrals"  => {'>=' => \'?'},
          "$args->{foreign_alias}.last_defer" => {'>', \'(LOCALTIMESTAMP - ?::interval)'},
        ],
      ],
    };
  },
  {cascade_copy => 0, cascade_update => 0, cascade_delete => 0}
);

=head2 target

Returns the single C<device> to which this Job entry was associated.

The JOIN is of type LEFT, in case the C<device> is not in the database.

=cut

# 定义关联关系：目标设备
# 返回与此任务条目关联的单个设备
__PACKAGE__->belongs_to(
  target => 'App::Netdisco::DB::Result::Device',
  {'foreign.ip' => 'self.device'}, {join_type => 'LEFT'}
);

=head1 METHODS

=head2 display_name

An attempt to make a meaningful statement about the job.

=cut

# 显示名称方法
# 尝试生成关于任务的有意义描述
sub display_name {
  my $job = shift;
  return join ' ', $job->action, ($job->device || ''), ($job->port || '');

#      ($job->subaction ? (q{'}. $job->subaction .q{'}) : '');
}

=head1 ADDITIONAL COLUMNS

=head2 entered_stamp

Formatted version of the C<entered> field, accurate to the minute.

The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:

 2012-02-06 12:49

=cut

# 进入时间戳方法
# 返回entered字段的格式化版本，精确到分钟
sub entered_stamp { return (shift)->get_column('entered_stamp') }

=head2 started_stamp

Formatted version of the C<started> field, accurate to the minute.

The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:

 2012-02-06 12:49

=cut

# 开始时间戳方法
# 返回started字段的格式化版本，精确到分钟
sub started_stamp { return (shift)->get_column('started_stamp') }

=head2 finished_stamp

Formatted version of the C<finished> field, accurate to the minute.

The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:

 2012-02-06 12:49

=cut

# 完成时间戳方法
# 返回finished字段的格式化版本，精确到分钟
sub finished_stamp { return (shift)->get_column('finished_stamp') }

=head2 duration

Difference between started and finished.

=cut

# 持续时间方法
# 返回开始时间和完成时间之间的差值
sub duration { return (shift)->get_column('duration') }

1;
