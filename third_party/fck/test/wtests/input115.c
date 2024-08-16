void cprintf(void *fmt, ...);

struct foo { int x; char y; long z; }; 
typedef struct foo blah;

// Symbol table structure
struct symtable {
  char *name;                   // Name of a symbol
  int type;                     // Primitive type for the symbol
  struct symtable *ctype;       // If struct/union, ptr to that type
  int stype;                    // Structural type for the symbol
  int class;                    // Storage class for the symbol
  int size;                     // Total size in bytes of this symbol
  int nelems;                   // Functions: # params. Arrays: # elements
#define st_endlabel st_posn     // For functions, the end label
  int st_posn;                  // For locals, the negative offset
                                // from the stack base pointer
  int *initlist;                // List of initial values
  struct symtable *next;        // Next symbol in one list
  struct symtable *member;      // First member of a function, struct,
};                              // union or enum

// Abstract Syntax Tree structure
struct ASTnode {
  int op;                       // "Operation" to be performed on this tree
  int type;                     // Type of any expression this tree generates
  int rvalue;                   // True if the node is an rvalue
  struct ASTnode *left;         // Left, middle and right child trees
  struct ASTnode *mid;
  struct ASTnode *right;
  struct symtable *sym;         // For many AST nodes, the pointer to
                                // the symbol in the symbol table
#define a_intvalue a_size       // For A_INTLIT, the integer value
  int a_size;                   // For A_SCALE, the size to scale by
};

int main() {
  cprintf("%d\n", sizeof(char));
  cprintf("%d\n", sizeof(int));
  cprintf("%d\n", sizeof(long));
  cprintf("%d\n", sizeof(char *));
  cprintf("%d\n", sizeof(blah));
  cprintf("%d\n", sizeof(struct symtable));
  cprintf("%d\n", sizeof(struct ASTnode));
  return(0);
}
