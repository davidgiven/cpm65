int printint(int x);
void putchar(int ch);

int fred() {
  return(56);
}

int main() {
  int dummy;
  int result;
  dummy= printint(23);
  result= fred(10);
  dummy= printint(result);
  return(0);
}
