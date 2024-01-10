#ifndef __wannier90_hh__
#define __wannier90_hh__

#include <ISO_Fortran_binding.h>
#include <complex>
#include <cstring>
#include <mpi.h>

extern "C" {
void cchkpt(void*, void*, CFI_cdesc_t*, CFI_cdesc_t*);
void ccreate_kmesh(void*);

void cinput_reader_special(void*, void*, CFI_cdesc_t*);
void cinput_reader(void*, void*, CFI_cdesc_t*);
void cinput_setopt(void*, void*, CFI_cdesc_t*);
void cset_option_float33(void*, CFI_cdesc_t*, void*);
void cset_option_float(void*, CFI_cdesc_t*, double);
void cset_option_floatxy(void*, CFI_cdesc_t*, void*, int, int);
void cset_option_int3(void*, CFI_cdesc_t*, void*);
void cset_option_int(void*, CFI_cdesc_t*, int);

void coverlaps(void*, void*);
void cdisentangle(void*, void*);
void cwannierise(void*, void*);

void* getglob(CFI_cdesc_t*);
void* getwann();

void cset_kpoint_distribution(void*, int*);
void cset_parallel_comms(void*, int);

void cset_a_matrix(void*, void*, std::complex<double>*);
void cset_eigval(void*, double*);
void cset_m_matrix_local(void*, void*, std::complex<double>*);
void cset_m_orig(void*, void*, std::complex<double>*);
void cset_u_matrix(void*, void*, std::complex<double>*);
void cset_u_opt(void*, void*, std::complex<double>*);

void cget_nn(void*, void*);
void cget_nnkp(void*, void*);
void cget_centres(void*, void*);
void cget_spreads(void*, void*);
}

void cset_parallel_comms(void* blob, MPI_Comm comm) {
        int fcomm = MPI_Comm_c2f(comm);
        cset_parallel_comms(blob, fcomm); // translate to fortran integer and set communicator
}

// see https://community.intel.com/t5/Intel-Fortran-Compiler/C-interoperablilty-and-character-strings/td-p/1084167
void cset_option(void* blob, std::string key, int x) {
        CFI_cdesc_t stringdesc;
        char* keyc = (char*)key.c_str(); // discarding constness
        CFI_establish(&stringdesc, keyc, CFI_attribute_other, CFI_type_char, strlen(keyc), 0, NULL);
        cset_option_int(blob, &stringdesc, x);
}
void cset_option(void* blob, std::string key, int x[3]) {
        CFI_cdesc_t stringdesc;
        char* keyc = (char*)key.c_str(); // discarding constness
        CFI_establish(&stringdesc, keyc, CFI_attribute_other, CFI_type_char, strlen(keyc), 0, NULL);
        cset_option_int3(blob, &stringdesc, &x);
}
void cset_option(void* blob, std::string key, double x[][3]) {
        CFI_cdesc_t stringdesc;
        char* keyc = (char*)key.c_str(); // discarding constness
        CFI_establish(&stringdesc, keyc, CFI_attribute_other, CFI_type_char, strlen(keyc), 0, NULL);
        cset_option_float33(blob, &stringdesc, &x);
}
void cset_option(void* blob, std::string key, double x) {
        CFI_cdesc_t stringdesc;
        char* keyc = (char*)key.c_str(); // discarding constness
        CFI_establish(&stringdesc, keyc, CFI_attribute_other, CFI_type_char, strlen(keyc), 0, NULL);
        cset_option_float(blob, &stringdesc, x);
}
void cset_option(void* blob, std::string key, double* x, int i1, int i2) {
        CFI_cdesc_t stringdesc;
        char* keyc = (char*)key.c_str(); // discarding constness
        CFI_establish(&stringdesc, keyc, CFI_attribute_other, CFI_type_char, strlen(keyc), 0, NULL);
        cset_option_floatxy(blob, &stringdesc, x, i1, i2);
}
void cinput_setopt(void* blob, void* blob2, std::string seed) {
        CFI_cdesc_t stringdesc;
        char* seedc = (char*)seed.c_str(); // discarding constness
        CFI_establish(&stringdesc, seedc, CFI_attribute_other, CFI_type_char, strlen(seedc), 0, NULL);
        cinput_setopt(blob, blob2, &stringdesc);
}
void cinput_reader(void* blob, void* blob2, std::string seed) {
        CFI_cdesc_t stringdesc;
        char* seedc = (char*)seed.c_str(); // discarding constness
        CFI_establish(&stringdesc, seedc, CFI_attribute_other, CFI_type_char, strlen(seedc), 0, NULL);
        cinput_reader(blob, blob2, &stringdesc);
}
void cinput_reader_special(void* blob, void* blob2, std::string seed) {
        CFI_cdesc_t stringdesc;
        char* seedc = (char*)seed.c_str(); // discarding constness
        CFI_establish(&stringdesc, seedc, CFI_attribute_other, CFI_type_char, strlen(seedc), 0, NULL);
        cinput_reader_special(blob, blob2, &stringdesc);
}
void* getglob(const std::string seed) {
        CFI_cdesc_t stringdesc;
        char* seedc = (char*)seed.c_str(); // discarding constness
        CFI_establish(&stringdesc, seedc, CFI_attribute_other, CFI_type_char, strlen(seedc), 0, NULL);
        return getglob(&stringdesc);
}
void cchkpt(void* blob, void* blob2, std::string seed, std::string text2) {
        CFI_cdesc_t stringdesc, desc2;
        char* seedc = (char*)seed.c_str(); // discarding constness
        char* text2c = (char*)text2.c_str(); // discarding constness
        CFI_establish(&stringdesc, seedc, CFI_attribute_other, CFI_type_char, strlen(seedc), 0, NULL);
        CFI_establish(&desc2, text2c, CFI_attribute_other, CFI_type_char, strlen(text2c), 0, NULL);
        cchkpt(blob, blob2, &stringdesc, &desc2);
}
#endif
