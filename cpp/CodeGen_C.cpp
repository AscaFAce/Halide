#include "CodeGen_C.h"
#include "Substitute.h"
#include "IROperator.h"
#include <iostream>

namespace HalideInternal {

    using std::ostream;
    using std::endl;

    CodeGen_C::CodeGen_C(ostream &s) : IRPrinter(s) {}

    void CodeGen_C::print_c_type(Type type) {
        assert(type.width == 1 && "Can't codegen vector types to C (yet)");
        if (type.is_float()) {
            if (type.bits == 32) {
                stream << "float";
            } else if (type.bits == 64) {
                stream << "double";
            } else {
                assert(false && "Can't represent a float with this many bits in C");
            }
            
        } else {
            switch (type.bits) {
            case 1:
                stream << "bool";
                break;
            case 8: case 16: case 32: case 64:
                if (type.is_uint()) stream << 'u';
                stream << "int" << type.bits << "_t";                
                break;
            default:
                assert(false && "Can't represent an integer with this many bits in C");                
            }
        }
    }

    void CodeGen_C::print_c_name(const string &name) {
        for (size_t i = 0; i < name.size(); i++) {
            if (name[i] == '.') stream << '_';
            else stream << name[i];
        }
    }

    void CodeGen_C::compile(Stmt s, string name, const vector<Argument> &args) {
        stream << "#include <iostream>" << endl;
        stream << "#include <assert.h>" << endl;
        stream << "#include \"buffer.h\"" << endl;


        // Emit the function prototype
        stream << "void " << name << "(";
        for (size_t i = 0; i < args.size(); i++) {
            if (args[i].is_buffer) {
                stream << "buffer_t *_";
                print_c_name(args[i].name);
            } else {
                print_c_type(args[i].type);
                stream << " ";
                print_c_name(args[i].name);
            }

            if (i < args.size()-1) stream << ", ";
        }

        stream << ") {" << endl;

        // Unpack the buffer_t's
        for (size_t i = 0; i < args.size(); i++) {
            if (args[i].is_buffer) {
                stream << "uint8_t *";
                print_c_name(args[i].name);
                stream << " = _";
                print_c_name(args[i].name);
                stream << "->host;" << endl;

                for (int j = 0; j < 4; j++) {
                    stream << "int32_t ";
                    print_c_name(args[i].name);
                    stream << "_min_" << j << " = _";
                    print_c_name(args[i].name);
                    stream << "->min[" << j << "];" << endl;
                }
                for (int j = 0; j < 4; j++) {
                    stream << "int32_t ";
                    print_c_name(args[i].name);
                    stream << "_extent_" << j << " = _";
                    print_c_name(args[i].name);
                    stream << "->extent[" << j << "];" << endl;
                }
                for (int j = 0; j < 4; j++) {
                    stream << "int32_t ";
                    print_c_name(args[i].name);
                    stream << "_stride_" << j << " = _";
                    print_c_name(args[i].name);
                    stream << "->stride[" << j << "];" << endl;
                }
            }
        }        

        print(s);

        stream << "}" << endl;
    }

    void CodeGen_C::visit(const Var *op) {
        print_c_name(op->name);
    }

    void CodeGen_C::visit(const Cast *op) { 
        stream << '(';
        print_c_type(op->type);
        stream << ")(";
        print(op->value);
        stream << ')';
    }

    void CodeGen_C::visit(const Load *op) {
        stream << "((";
        print_c_type(op->type);
        stream << " *)";
        print_c_name(op->buffer);
        stream << ")[";
        print(op->index);
        stream << "]";
    }

    void CodeGen_C::visit(const Store *op) {
        do_indent();
        Type t = op->value.type();
        stream << "((";
        print_c_type(t);
        stream << " *)";
        print_c_name(op->buffer);
        stream << ")[";
        print(op->index);
        stream << "] = ";
        print(op->value);
        stream << ";" << endl;
    }

    void CodeGen_C::visit(const Let *op) {
        // Let expressions don't really work in C
        // Just do a substitution instead
        Expr e = substitute(op->name, op->value, op->body);
        e.accept(this);
    }

    void CodeGen_C::visit(const Select *op) {
        stream << "(";
        print(op->condition);
        stream << " ? ";
        print(op->true_value);
        stream << " : ";
        print(op->false_value);
        stream << ")";
    }

    void CodeGen_C::visit(const LetStmt *op) {
        do_indent();
        stream << "{" << endl;
        indent += 2;

        do_indent();
        print_c_type(op->value.type());
        stream << " ";
        print_c_name(op->name);
        stream << " = ";
        op->value.accept(this);
        stream << ";" << endl;

        op->body.accept(this);

        do_indent();
        stream << "}" << endl;

        indent -= 2;
    }

    void CodeGen_C::visit(const PrintStmt *op) {
        do_indent();
        
        string format_string;
        stream << "std::cout << " << op->prefix;

        for (size_t i = 0; i < op->args.size(); i++) {
            stream << " << ";
            op->args[i].accept(this);
        }
        stream << ";" << endl;
    }

    void CodeGen_C::visit(const AssertStmt *op) {
        do_indent();
        stream << "assert(";
        op->condition.accept(this);
        stream << " && \"" << op->message << "\");" << endl;
    }

    void CodeGen_C::visit(const Pipeline *op) {

        do_indent();
        stream << "// produce " << op->buffer << endl;
        op->produce.accept(this);

        if (op->update.defined()) {
            do_indent();
            stream << "// update " << op->buffer << endl;
            op->update.accept(this);            
        }
        
        do_indent();
        stream << "// consume " << op->buffer << endl;
        op->consume.accept(this);
    }

    void CodeGen_C::visit(const For *op) {
        if (op->for_type == For::Parallel) {
            do_indent();
            stream << "#pragma omp parallel for" << endl;
        } else {
            assert(op->for_type == For::Serial && "Can only emit serial or parallel for loops to C");
        }       

        do_indent();
        stream << "for (int ";
        print_c_name(op->name);
        stream << " = ";
        op->min.accept(this);
        stream << "; ";
        print_c_name(op->name);
        stream << " < ";
        op->min.accept(this);
        stream << " + ";
        op->extent.accept(this);
        stream << "; ";
        print_c_name(op->name);
        stream << "++) {" << endl;
        
        indent += 2;
        op->body.accept(this);
        indent -= 2;

        do_indent();
        stream << "}" << endl;
    }

    void CodeGen_C::visit(const Provide *op) {
        assert(false && "Cannot emit Provide statements as C");
    }

    void CodeGen_C::visit(const Allocate *op) {
        do_indent();
        stream << "{" << endl;
        indent += 2;

        do_indent();
        print_c_type(op->type);
        stream << ' ';

        // For sizes less than 32k, do a stack allocation
        bool on_stack = false;
        int stack_size = 0;
        if (const IntImm *sz = op->size.as<IntImm>()) {
            stack_size = sz->value;
            on_stack = stack_size <= 32*1024;
        }

        if (on_stack) {
            print_c_name(op->buffer);
            stream << "[" << stack_size << "];" << endl;
        } else {        
            stream << "*";
            print_c_name(op->buffer);
            stream << " = new ";
            print_c_type(op->type);
            stream << "[";
            op->size.accept(this);
            stream << "];" << endl;
        }

        op->body.accept(this);            

        if (!on_stack) {
            do_indent();
            stream << "delete[] ";
            print_c_name(op->buffer);
            stream << ";" << endl;
        }

        indent -= 2;
        do_indent();
        stream << "}" << endl;
    }

    void CodeGen_C::visit(const Realize *op) {
        assert(false && "Cannot emit realize statements to C");
    }

    void CodeGen_C::test() {
        Argument buffer_arg = {"buf", true, Int(0)};
        Argument float_arg = {"alpha", false, Float(32)};
        Argument int_arg = {"beta", false, Int(32)};
        vector<Argument> args(3);
        args[0] = buffer_arg;
        args[1] = float_arg;
        args[2] = int_arg;
        Expr x = new Var(Int(32), "x");
        Expr alpha = new Var(Float(32), "alpha");
        Expr beta = new Var(Int(32), "beta");
        Expr e = new Select(alpha > 4.0f, 3, 2);
        Stmt s = new Store("buf", e, x);
        s = new LetStmt("x", beta+1, s);
        s = new Allocate("tmp.stack", Int(32), 127, s);
        s = new Allocate("tmp.heap", Int(32), 43 * beta, s);

        CodeGen_C cg(std::cout);
        cg.compile(s, "test1", args);
    }

}
