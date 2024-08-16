extern unsigned assign_storage(unsigned type, unsigned storage);
extern unsigned alloc_room(unsigned *offset, unsigned type, unsigned storage);

extern void mark_storage(unsigned *a, unsigned *b);
extern void pop_storage(unsigned *a, unsigned *b);

extern unsigned frame_size(void);
extern unsigned arg_size(void);
extern void init_storage(void);

extern struct symbol *reg_load[NUM_REG + 1];
extern unsigned reg_offset[NUM_REG + 1];
