'''
Use the convention every position at C-level is 0-based. If the position is
accessed by property mechanism from python layer it should be one based.

Created on 2011-07-28

@author: Andrew Roth
'''
cdef class JointBinaryQualityCounter(Counter):
    '''
    Class for iterating over positions from paired genome files counting bases.
    '''
    def __init__(self, Samfile normal_bam, Samfile tumour_bam, Fastafile ref_genome_fasta):
        self._normal_counter = QualityCounter(normal_bam)
        self._tumour_counter = QualityCounter(tumour_bam)
        
        self._ref_genome_fasta = ref_genome_fasta
        
        self._refs = tuple(set(self._normal_counter.refs) & set(self._tumour_counter.refs)) 
        
    def iter_ref(self, ref):
        if ref not in self._refs:
            raise Exception("Invalid reference passed.")
        
        return JointBinaryQualityCounterIterator(
                                                 ref,
                                                 self._normal_counter.iter_ref(ref),
                                                 self._tumour_counter.iter_ref(ref),
                                                 self._ref_genome_fasta
                                                 )
        
cdef class JointBinaryQualityCounterIterator(CounterRefIterator):
    def __init__(self,
                 char * ref,
                 QualityCounterRefIterator normal_iter,
                 QualityCounterRefIterator tumour_iter,
                 Fastafile ref_genome_fasta):
        
        self._ref = ref
        
        self._normal_iter = normal_iter
        self._tumour_iter = tumour_iter
        
        self._ref_genome_fasta = ref_genome_fasta
        
        self._position = -1

    cdef cnext(self):        
        cdef QualityCounterRow normal_row
        cdef QualityCounterRow tumour_row
        
        cdef int normal_pos
        cdef int tumour_pos
        
        self._normal_iter.cnext()
        self._normal_row = self._normal_iter._current_row
        
        self._tumour_iter.cnext()
        self._tumour_row = self._tumour_iter._current_row
        
        while True:
            normal_pos = self._normal_row._position
            tumour_pos = self._tumour_row._position
            
            if normal_pos == tumour_pos:
                self._position = normal_pos
                
                self._set_current_row()
                
                break             
            elif normal_pos < tumour_pos:
                self._normal_iter.cnext()
                self._normal_row = self._normal_iter._current_row
            elif normal_pos > tumour_pos:
                self._tumour_iter.cnext()
                self._tumour_row = self._tumour_iter._current_row
            else:
                raise Exception("Error in joint pileup iterator.")
    
    cdef _set_current_row(self):
        cdef int region_length
        cdef char * ref_base
        
        region_length = 1 
        
        ref_base = self._ref_genome_fasta._fetch(
                                                 self._normal_row._ref,
                                                 self._normal_row._position,
                                                 self._normal_row._position + 1,
                                                 & region_length
                                                 )
    
        self._current_row = makeJointBinaryQualityCounterRow(ref_base, self._normal_row, self._tumour_row)
    
cdef class JointBinaryQualityCounterRow
cdef JointBinaryQualityCounterRow makeJointBinaryQualityCounterRow(char * ref_base, 
                                                                   QualityCounterRow normal_row, 
                                                                   QualityCounterRow tumour_row):
    '''
    Constructor method for creating a JointBinaryQualityCounterRow from C.
    '''
    cdef char * non_ref_base

    cdef JointBinaryQualityCounterRow row = JointBinaryQualityCounterRow.__new__(JointBinaryQualityCounterRow)
    
    row._ref = normal_row._ref
    row._position = normal_row._position
    
    row._ref_base = ref_base
    
    non_ref_base = get_non_ref_base(ref_base, normal_row, tumour_row)
    
    row._non_ref_base = non_ref_base
     
    row._normal_row = normal_row
    row._tumour_row = tumour_row    
     
    return row

cdef class JointBinaryQualityCounterRow(CounterRow):
    '''
    Class for storing binary count data from a pair of Bam files at a position.
    '''    
    def __init__(self):
        raise TypeError("This class cannot be instantiated from Python")
    
    def __str__(self):
        '''
        Overide parent class method to include ref and non_ref base.
        '''
        out_row = [self.ref, str(self.position), self.ref_base, self.non_ref_base]
        out_row.extend([str(x) for x in self.counts])
        
        return "\t".join(out_row)
    
    property counts:
        def __get__(self):
            return (
                    self._normal_row.counts,
                    self._tumour_row.counts
                    )
    
    property depth:
        def __get__(self):
            if self._normal_row.depth < self._tumour_row.depth:
                return self._normal_row.depth
            else:
                return self._tumour_row.depth
        
    property ref_base:
        def __get__(self):
            return self._ref_base

    property non_ref_base:
        def __get__(self):
            return self._non_ref_base
    
#===============================================================================
# Utility functions for finding non-ref bases and counts.
#===============================================================================
cdef int compare_base_counts_struct(const_void * a, const_void * b):
    cdef base_counts_struct * first
    cdef base_counts_struct * second
    
    first = < base_counts_struct *> a
    second = < base_counts_struct *> b

    return first.counts - second.counts

cdef char * get_non_ref_base(char * ref_base, QualityCounterRow normal_row, QualityCounterRow tumour_row):
    '''
    Sort the bases by number observed and return the most common non-reference base.
    
    Return N if the counts of most common non-reference is 0.
    ''' 
    cdef int non_ref_index    
    cdef base_counts_struct[4] counts

    counts[0] = normal_row.get_base_counts("A")
    counts[1] = normal_row.get_base_counts("C")
    counts[2] = normal_row.get_base_counts("G")
    counts[3] = normal_row.get_base_counts("T")
    
    counts[0].counts += tumour_row.get_counts("A")
    counts[1].counts += tumour_row.get_counts("C")
    counts[2].counts += tumour_row.get_counts("G")
    counts[3].counts += tumour_row.get_counts("T")

    # Sort the structs by counts field. 
    qsort(counts, 4, sizeof(base_counts_struct), compare_base_counts_struct)
            
    # If the most prevalent base is not the reference return it.
    if strcmp(counts[3].base, ref_base) != 0:
        non_ref_index = 3
    else:
        non_ref_index = 2
    
    if counts[non_ref_index].counts > 0:
        return counts[non_ref_index].base
    else:
        return 'N'
        
cdef binary_counts_struct get_binary_counts(char * ref_base, char * non_ref_base, QualityCounterRow row):
    cdef binary_counts_struct counts

    counts.A = row.get_counts(ref_base)
    counts.B = row.get_counts(non_ref_base)
    
    return counts 
