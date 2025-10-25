use utf8;
package App::Netdisco::DB::Result::DeviceSkip;

# 设备跳过结果类
# 提供设备跳过和延迟机制的管理模型

use strict;
use warnings;

use List::MoreUtils ();

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("device_skip");

# 定义表列
# 包含后端、设备、动作集合、延迟次数和最后延迟时间
__PACKAGE__->add_columns(
  "backend",    {data_type => "text",      is_nullable => 0},
  "device",     {data_type => "inet",      is_nullable => 0},
  "actionset",  {data_type => "text[]",    is_nullable => 1, default_value => \"'{}'::text[]"},
  "deferrals",  {data_type => "integer",   is_nullable => 1, default_value => '0'},
  "last_defer", {data_type => "timestamp", is_nullable => 1},
);

# 设置主键
__PACKAGE__->set_primary_key("backend", "device");

# 添加唯一约束
__PACKAGE__->add_unique_constraint(device_skip_pkey => [qw/backend device/]);

=head1 METHODS

=head2 increment_deferrals

Increments the C<deferrals> field in the row, only if the row is in storage.
There is a race in the update, but this is not worrying for now.

=cut

# 增加延迟次数方法
# 增加行中的deferrals字段，仅当行在存储中时。更新中存在竞争，但目前不担心
sub increment_deferrals {
  my $row = shift;
  return unless $row->in_storage;
  return $row->update({deferrals => (($row->deferrals || 0) + 1), last_defer => \'LOCALTIMESTAMP',});
}

=head2 add_to_actionset

=cut

# 添加到动作集合方法
# 将新的动作添加到动作集合中，去重并排序
sub add_to_actionset {
  my ($row, @badactions) = @_;
  return unless $row->in_storage;
  return unless scalar @badactions;
  return $row->update({actionset => [sort (List::MoreUtils::uniq(@{$row->actionset || []}, @badactions))]});
}

1;
