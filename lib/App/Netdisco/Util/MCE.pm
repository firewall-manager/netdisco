package App::Netdisco::Util::MCE;

# MCE工具模块
# 提供多核处理相关的辅助功能

use strict;
use warnings;

use MCE::Util ();

use base 'Exporter';
our @EXPORT = qw/prctl parse_max_workers/;

# 设置进程标题
sub prctl { $0 = shift }

# 解析最大工作进程数
# 支持auto模式和数学运算
sub parse_max_workers {
  my $max = shift;
  return 0 if !defined $max;

  # 处理auto模式，支持数学运算
  if ($max =~ /^auto(?:$|\s*([\-\+\/\*])\s*(.+)$)/i) {
      my $ncpu = MCE::Util::get_ncpu() || 0;

      if ($1 and $2) {
          local $@; $max = eval "int($ncpu $1 $2 + 0.5)";
      }
  }

  return $max || 0;
}

1;
