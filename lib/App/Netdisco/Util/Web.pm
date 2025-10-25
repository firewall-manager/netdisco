package App::Netdisco::Util::Web;

# Web工具模块
# 支持Netdisco应用程序各个部分的辅助子程序

use strict;
use warnings;

use Dancer ':syntax';

use Time::Piece;
use Time::Seconds;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  sort_port sort_modules
  interval_to_daterange
  sql_match
  request_is_device
  request_is_api
  request_is_api_report
  request_is_api_search
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Web

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 request_is_device

Client has requested device content under C<.../device> or C<.../device/ports>.

=cut

# 检查是否为设备请求
# 客户端已请求.../device或.../device/ports下的设备内容
sub request_is_device {
  return (
    index(request->path, uri_for('/device')->path) == 0
      or
    index(request->path, uri_for('/ajax/content/device/details')->path) == 0
      or
    index(request->path, uri_for('/ajax/content/device/ports')->path) == 0
  );
}

=head2 request_is_api

Client has requested JSON format data and an endpoint under C</api>.

=cut

# 检查是否为API请求
# 客户端已请求JSON格式数据和/api下的端点
sub request_is_api {
  return ((request->accept and request->accept =~ m/(?:json|javascript)/) and (
    index(request->path, uri_for('/api/')->path) == 0
      or
    (param('return_url')
    and index(param('return_url'), uri_for('/api/')->path) == 0)
  ));
}

=head2 request_is_api_report

Same as C<request_is_api> but also requires path to start "C</api/v1/report/...>".

=cut

# 检查是否为API报告请求
# 与request_is_api相同，但还需要路径以"/api/v1/report/..."开始
sub request_is_api_report {
  return (request_is_api and (
    index(request->path, uri_for('/api/v1/report/')->path) == 0
      or
    (param('return_url')
    and index(param('return_url'), uri_for('/api/v1/report/')->path) == 0)
  ));
}

=head2 request_is_api_search

Same as C<request_is_api> but also requires path to start "C</api/v1/search/...>".

=cut

# 检查是否为API搜索请求
# 与request_is_api相同，但还需要路径以"/api/v1/search/..."开始
sub request_is_api_search {
  return (request_is_api and (
    index(request->path, uri_for('/api/v1/search/')->path) == 0
      or
    (param('return_url')
    and index(param('return_url'), uri_for('/api/v1/search/')->path) == 0)
  ));
}

=head2 sql_match( $value, $exact? )

Convert wildcard characters "C<*>" and "C<?>" to "C<%>" and "C<_>"
respectively.

Pass a true value to C<$exact> to only substitute the existing wildcards, and
not also add "C<*>" to each end of the value.

In list context, returns two values, the translated value, and also an
L<SQL::Abstract> LIKE clause.

=cut

# SQL匹配
# 将通配符字符"*"和"?"分别转换为"%"和"_"
sub sql_match {
  my ($text, $exact) = @_;
  return unless $text;

  $text =~ s/^\s+//;
  $text =~ s/\s+$//;

  $text =~ s/[*]+/%/g;
  $text =~ s/[?]/_/g;

  $text = '%'. $text . '%' unless $exact;
  $text =~ s/\%+/%/g;

  return ( wantarray ? ($text, {-ilike => $text}) : $text );
}

=head2 sort_port( $a, $b )

Sort port names of various types used by device vendors. Interface is as
Perl's own C<sort> - two input args and an integer return value.

=cut

# 端口排序
# 排序设备供应商使用的各种类型的端口名称
sub sort_port {
    my ($aval, $bval) = @_;

    # 针对foundry的"10GigabitEthernet" -> cisco风格的"TenGigabitEthernet"的hack
    $aval = $1 if $aval =~ qr/^10(GigabitEthernet.+)$/;
    $bval = $1 if $bval =~ qr/^10(GigabitEthernet.+)$/;

    my $numbers        = qr{^(\d+)$};
    my $numeric        = qr{^([\d\.]+)$};
    my $dotted_numeric = qr{^(\d+)[:.](\d+)$};
    my $letter_number  = qr{^([a-zA-Z]+)(\d+)$};
    my $wordcharword   = qr{^([^:\/.]+)[-\ :\/\.]+([^:\/.0-9]+)(\d+)?$}; #port-channel45
    my $netgear        = qr{^Slot: (\d+) Port: (\d+) }; # "Slot: 0 Port: 15 Gigabit - Level"
    my $ciscofast      = qr{^
                            # 单词数字斜杠 (Gigabit0/)
                            (\D+)(\d+)[\/:]
                            # 符号浮点数组 (/5.5/5.5/5.5)，用斜杠或冒号分隔
                            ([\/:\.\d]+)
                            # 可选破折号 (-Bearer Channel)
                            (-.*)?
                            $}x;

    my @a = (); my @b = ();

    if ($aval =~ $dotted_numeric) {
        @a = ($1,$2);
    } elsif ($aval =~ $letter_number) {
        @a = ($1,$2);
    } elsif ($aval =~ $netgear) {
        @a = ($1,$2);
    } elsif ($aval =~ $numbers) {
        @a = ($1);
    } elsif ($aval =~ $ciscofast) {
        @a = ($1,$2);
        push @a, split(/[:\/]/,$3), $4;
    } elsif ($aval =~ $wordcharword) {
        @a = ($1,$2,$3);
    } else {
        @a = ($aval);
    }

    if ($bval =~ $dotted_numeric) {
        @b = ($1,$2);
    } elsif ($bval =~ $letter_number) {
        @b = ($1,$2);
    } elsif ($bval =~ $netgear) {
        @b = ($1,$2);
    } elsif ($bval =~ $numbers) {
        @b = ($1);
    } elsif ($bval =~ $ciscofast) {
        @b = ($1,$2);
        push @b, split(/[:\/]/,$3),$4;
    } elsif ($bval =~ $wordcharword) {
        @b = ($1,$2,$3);
    } else {
        @b = ($bval);
    }

    # 在证明其他情况之前相等
    my $val = 0;
    while (scalar(@a) or scalar(@b)){
        # 从上次查找中携带过来
        last if $val != 0;

        my $a1 = shift @a;
        my $b1 = shift @b;

        # A有更多组件 - 失败
        unless (defined $b1){
            $val = 1;
            last;
        }

        # A有更少组件 - 获胜
        unless (defined $a1) {
            $val = -1;
            last;
        }

        if ($a1 =~ $numeric and $b1 =~ $numeric){
            $val = $a1 <=> $b1;
        } elsif ($a1 ne $b1) {
            $val = $a1 cmp $b1;
        }
    }

    return $val;
}

=head2 sort_modules( $modules )

Sort devices modules into tree hierarchy based upon position and parent -
input arg is module list.

=cut

# 模块排序
# 根据位置和父级将设备模块排序为树层次结构
sub sort_modules {
    my $input = shift;
    my %modules;

    foreach my $module (@$input) {
        $modules{$module->index}{module} = $module;
        if ($module->parent) {
            # 示例
            # index |              描述                      |        类型          | parent |  class  | pos 
            #-------+----------------------------------------+---------------------+--------+---------+-----
            #     1 | Cisco Aironet 1200 Series Access Point | cevChassisAIRAP1210 |      0 | chassis |  -1
            #     3 | PowerPC405GP Ethernet                  | cevPortFEIP         |      1 | port    |  -1
            #     2 | 802.11G Radio                          | cevPortUnknown      |      1 | port    |   0

            # 某些设备没有正确实现，所以给定的父级
            # 可以在单个pos值处具有同一类中的多个项目
            # 但是，数据库结果按1）父级2）类3）pos 4）索引排序，所以我们应该能够推送到
            # 数组并保持排序
            {
              no warnings 'uninitialized';
              push(@{$modules{$module->parent}{children}{$module->class}}, $module->index);
            }
        } else {
            push(@{$modules{root}}, $module->index);
        }
    }
    return \%modules;
}

=head2 interval_to_daterange( $interval )

Takes an interval in days, weeks, months, or years in a format like '7 days'
and returns a date range in the format 'YYYY-MM-DD to YYYY-MM-DD' by
subtracting the interval from the current date.

If C<$interval> is not passed, epoch zero (1970-01-01) is used as the start.

=cut

# 时间间隔转日期范围
# 获取天、周、月或年的间隔，格式如'7 days'，并通过从当前日期减去间隔返回'YYYY-MM-DD to YYYY-MM-DD'格式的日期范围
sub interval_to_daterange {
    my $interval = shift;

    unless ($interval
        and $interval =~ m/^(?:\d+)\s+(?:day|week|month|year)s?$/) {

        return "1970-01-01 to " . Time::Piece->new->ymd;
    }

    my %const = (
        day   => ONE_DAY,
        week  => ONE_WEEK,
        month => ONE_MONTH,
        year  => ONE_YEAR
    );

    my ( $amt, $factor )
        = $interval =~ /^(\d+)\s+(day|week|month|year)s?$/gmx;

    $amt-- if $factor eq 'day';

    my $start = Time::Piece->new - $const{$factor} * $amt;

    return $start->ymd . " to " . Time::Piece->new->ymd;
}

1;
