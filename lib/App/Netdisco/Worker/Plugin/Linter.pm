package App::Netdisco::Worker::Plugin::Linter;

# 代码检查工作器插件
# 提供代码质量检查和Python工作器增强功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;

# 演示如何将内容放入vars
# 并用其他内容包装/增强Python工作器

# 注册早期阶段工作器
# 设置代码检查文件路径
register_worker({ phase => 'early' }, sub {
  my ($job, $workerconf) = @_;
  my $file = $job->extra and return;

  # 设置要检查的文件路径
  vars->{'file_to_lint'} ||=
    Path::Class::Dir->new( $ENV{DANCER_ENVDIR} )
      ->file( $ENV{DANCER_ENVIRONMENT} .'.yml' )->stringify;
});

true;
