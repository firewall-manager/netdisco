package App::Netdisco::Worker::Status;

# 工作器状态类
# 提供工作器执行状态的管理功能

use strict;
use warnings;

use Dancer qw/:moose :syntax !error !info/;

use Moo;
use namespace::clean;

# 定义状态属性
# 包含状态、日志和阶段信息
has 'status' => (
  is => 'rw',
  default => undef,
);

has [qw/log phase/] => (
  is => 'rw',
  default => '',
);

=head1 INTRODUCTION

The status can be:

=over 4

=item * C<done>

Indicates a state of success and a log message which may be used as the
outcome for the action.

=item * C<info>

The worker has completed successfully and a debug log will be issued, but the
outcome is not the main goal of the action.

=item * C<defer>

Issued when the worker has failed to connect to the remote device, or is not
permitted to connect (through user config).

=item * C<error>

Something went wrong which should not normally be the case.

=item * C<()>

This is not really a status. The worker can return any value not an instance
of this class to indicate a "pass", or non-error conclusion.

=back

=head1 METHODS

=head2 done, info, defer, error

Shorthand for new() with setting param, accepts log as arg.

=cut

# 创建新状态方法
# 创建具有指定状态和日志的新状态对象
sub _make_new {
  my ($self, $status, $log) = @_;
  die unless $status;
  my $new = (ref $self ? $self : $self->new());
  $new->log($log);
  $new->status($status);
  return $new;
}

# 状态创建方法
sub done  { shift->_make_new('done', @_)  } # 完成状态
sub info  { shift->_make_new('info', @_)  } # 信息状态
sub defer { shift->_make_new('defer', @_) } # 延迟状态
sub error { shift->_make_new('error', @_) } # 错误状态

=head2 is_ok

Returns true if status is C<done>.

=cut

# 检查是否成功方法
# 如果状态为'done'则返回true
sub is_ok { return $_[0]->status eq 'done' }

# 检查是否不成功方法
# 如果状态是'error'、'defer'或'info'则返回true
sub not_ok { return (not $_[0]->is_ok) }

# 状态级别方法
# 返回状态的数字常量，用于比较
sub level {
  my $self = shift;
  return (($self->status eq 'error') ? 4
        : ($self->status eq 'done')  ? 3
        : ($self->status eq 'defer') ? 2
        : ($self->status eq 'info')  ? 1 : 0);
}

1;
