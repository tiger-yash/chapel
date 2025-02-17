use FileSystem;
use MasonInit;
use MasonUtils;
use MasonNew;

proc main(){
  const newArgs = ['new','testSrc'];
  masonNew(newArgs);
  runCommand('rm -rf testSrc/Mason.toml');
  const initArgs = ['init','testSrc'];
  masonInit(initArgs);
  //check if src and src/testSrc.chpl was created
  if isFile("./testSrc/Mason.toml") {
    writeln("Mason.toml has been successfully created");
  }
  rmTree("testSrc");
}
