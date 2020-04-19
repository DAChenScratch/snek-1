#include "cnek.h"

VALUE rb_mCnek;
VALUE rb_cCnekGrid;

static VALUE i_x, i_y;

/* Cnek::Grid */

struct snake_grid {
  unsigned int width;
  unsigned int height;
  VALUE *values;
};

static VALUE allocate_grid(VALUE klass) {
  struct snake_grid *grid;
  VALUE obj = Data_Make_Struct(klass, struct snake_grid, NULL, NULL, grid);

  grid->width = grid->height = 0;
  grid->values = NULL;

  return obj;
}

static VALUE rb_cnekgrid_initialize(VALUE self, VALUE width, VALUE height) {
  struct snake_grid *grid;
  Data_Get_Struct(self, struct snake_grid, grid);

  grid->width = NUM2UINT(width);
  grid->height = NUM2UINT(height);
  grid->values = xcalloc(grid->width * grid->height, sizeof(VALUE));

  return Qnil;
}

static void grid_bounds_check(struct snake_grid *grid, unsigned int x, unsigned int y) {
  if (x >= grid->width || y >= grid->height) {
    rb_raise(rb_eArgError, "point out of range");
  }
}

static VALUE rb_cnekgrid_set(VALUE self, VALUE xval, VALUE yval, VALUE value) {
  struct snake_grid *grid;
  Data_Get_Struct(self, struct snake_grid, grid);

  unsigned int x = FIX2INT(xval);
  unsigned int y = FIX2INT(yval);

  grid_bounds_check(grid, x, y);

  grid->values[y * grid->width + x] = value;

  return value;
}

static VALUE rb_cnekgrid_set_all(VALUE self, VALUE points, VALUE value) {
  for (unsigned int i = 0; i < RARRAY_LEN(points); i++) {
    VALUE point = RARRAY_AREF(points, i);
    VALUE x = rb_funcall(point, i_x, 0);
    VALUE y = rb_funcall(point, i_y, 0);
    rb_cnekgrid_set(self, x, y, value);
  }
}

static VALUE rb_cnekgrid_at(VALUE self, VALUE xval, VALUE yval) {
  struct snake_grid *grid;
  Data_Get_Struct(self, struct snake_grid, grid);

  unsigned int x = FIX2INT(xval);
  unsigned int y = FIX2INT(yval);

  grid_bounds_check(grid, x, y);

  return grid->values[y * grid->width + x];
}

/* Cnek::Queue */

#define QUEUE_MAX_LEN 1024
struct snake_queue {
  VALUE visited_obj;
  struct snake_grid *visited;

  int length;
  struct {
    unsigned int x;
    unsigned int y;
    VALUE val;
  } entries[QUEUE_MAX_LEN];
};

static VALUE allocate_queue(VALUE klass) {
  struct snake_queue *queue;
  VALUE obj = Data_Make_Struct(klass, struct snake_queue, NULL, NULL, queue);

  queue->length = 0;
  queue->visited_obj = Qnil;
  queue->visited = NULL;

  return obj;
}

static VALUE rb_cnekqueue_initialize(VALUE self, VALUE grid_value) {
  struct snake_queue *queue;
  Data_Get_Struct(self, struct snake_queue, queue);

  struct snake_grid *grid;
  Data_Get_Struct(grid_value, struct snake_grid, grid);

  queue->visited_obj = grid_value;
  queue->visited = grid;

  return Qnil;
}

static VALUE rb_cnekqueue_empty(VALUE self) {
  struct snake_queue *queue;
  Data_Get_Struct(self, struct snake_queue, queue);

  return queue->length == 0 ? Qtrue : Qfalse;
}

static void queue_add(struct snake_queue *queue, unsigned int x, unsigned int y, VALUE val) {
  queue->entries[queue->length].x = x;
  queue->entries[queue->length].y = y;
  queue->entries[queue->length].val = val;
  queue->length++;
}

static VALUE rb_cnekqueue_add(VALUE self, VALUE x, VALUE y, VALUE val) {
  struct snake_queue *queue;
  Data_Get_Struct(self, struct snake_queue, queue);

  if (queue->length >= QUEUE_MAX_LEN) {
    rb_raise(rb_eRuntimeError, "queue too big");
  }

  queue_add(queue, FIX2UINT(x), FIX2UINT(y), val);

  return Qnil;
}

static VALUE rb_cnekqueue_add_neighbours(VALUE self, VALUE xval, VALUE yval, VALUE val) {
  struct snake_queue *queue;
  Data_Get_Struct(self, struct snake_queue, queue);
  struct snake_grid *grid = queue->visited;

  if (queue->length + 4 > QUEUE_MAX_LEN) {
    rb_raise(rb_eRuntimeError, "queue too big");
  }

  unsigned int x = FIX2INT(xval);
  unsigned int y = FIX2INT(yval);


  if (x < grid->width - 1)
    queue_add(queue, x+1, y, val);
  if (x > 0)
    queue_add(queue, x-1, y, val);
  if (y < grid->height - 1)
    queue_add(queue, x, y+1, val);
  if (y > 0)
    queue_add(queue, x, y-1, val);

  return self;
}

static VALUE rb_cnekqueue_each(VALUE self) {
  struct snake_queue *queue;
  Data_Get_Struct(self, struct snake_queue, queue);
  struct snake_grid *grid = queue->visited;

  for (int i = 0; i < queue->length; i++) {
    unsigned int x = queue->entries[i].x;
    unsigned int y = queue->entries[i].y;

    if (grid->values[y * grid->width + x]) {
      continue;
    }
    grid->values[y * grid->width + x] = Qtrue;

    rb_yield_values(3,
        INT2FIX(x),
        INT2FIX(y),
        queue->entries[i].val);
  }

  return self;
}

static VALUE rb_cnekqueue_clear(VALUE self) {
  struct snake_queue *queue;
  Data_Get_Struct(self, struct snake_queue, queue);

  queue->length = 0;

  return self;
}

void
Init_cnek(void)
{
  i_x = rb_intern("x");
  i_y = rb_intern("y");

  rb_mCnek = rb_define_module("Cnek");

  rb_cCnekGrid = rb_define_class_under(rb_mCnek, "Queue", rb_cObject);
  rb_define_alloc_func(rb_cCnekGrid, allocate_queue);
  rb_define_method(rb_cCnekGrid, "initialize", rb_cnekqueue_initialize, 1);
  rb_define_method(rb_cCnekGrid, "add", rb_cnekqueue_add, 3);
  rb_define_method(rb_cCnekGrid, "add_neighbours", rb_cnekqueue_add_neighbours, 3);
  rb_define_method(rb_cCnekGrid, "each", rb_cnekqueue_each, 0);
  rb_define_method(rb_cCnekGrid, "empty?", rb_cnekqueue_empty, 0);
  rb_define_method(rb_cCnekGrid, "clear", rb_cnekqueue_clear, 0);

  rb_cCnekGrid = rb_define_class_under(rb_mCnek, "Grid", rb_cObject);
  rb_define_alloc_func(rb_cCnekGrid, allocate_grid);
  rb_define_method(rb_cCnekGrid, "initialize", rb_cnekgrid_initialize, 2);
  rb_define_method(rb_cCnekGrid, "set_all", rb_cnekgrid_set_all, 2);
  rb_define_method(rb_cCnekGrid, "at", rb_cnekgrid_at, 2);
  rb_define_method(rb_cCnekGrid, "set", rb_cnekgrid_set, 3);
}
