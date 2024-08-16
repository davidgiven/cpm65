void printint(int x);
void putchar(int ch);

int fred() {
  return(20);
}

int main() {
  int result;
  printint(10);
  result= fred(15);
  printint(result);
  printint(fred(15)+10);
  return(0);
}
