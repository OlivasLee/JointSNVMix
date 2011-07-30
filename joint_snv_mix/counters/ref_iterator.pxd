from libc.stdlib cimport malloc, free

from csamtools cimport IteratorColumnRegion, PileupProxy, bam1_t, bam1_seq, bam1_qual, \
                                             bam_pileup1_t, bam_dup1, bam_destroy1

from joint_snv_mix.counters.shared cimport column_struct

cdef extern from "stdint.h":
    ctypedef int uint8_t

cdef class CRefIterator(object):
    cdef char * _ref
    cdef int _position
    cdef column_struct _current_column
    
    cdef IteratorColumnRegion _pileup_iter
    cdef PileupProxy _current_pileup_column

    cdef cnext(self)
    cdef advance_position(self)
    cdef parse_current_position(self)
    
    cdef column_struct _parse_pileup_column(self, PileupProxy pileup_column)    
    cdef int _get_depth(self, PileupProxy pileup_column)
    
cdef column_struct make_column_struct(char * ref, int position, int depth)
cdef void destroy_column_struct(column_struct column)