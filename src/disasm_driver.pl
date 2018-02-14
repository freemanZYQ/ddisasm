:-module(disasm_driver,[disasm_binary/1]).


valid_option('-hints').
valid_option('-debug').
valid_option('-asm').

sections([
		%	'.eh_frame',
		'.text',
		'.plt',
		'.init',
		'.fini']).
data_sections([
		     '.got',
		     '.plt.got',
		      '.got.plt',
		     '.data',
		     '.rodata']).

analysis_file('souffle_main.pl').

disasm_binary([File|Args]):-
    maplist(save_option,Args),
    set_prolog_flag(print_write_options,[quoted(false)]),
    format('Decoding binary~n',[]),
    file_directory_name(File, Dir),
    atom_concat(Dir,'/dl_files',Dir2),
    (\+exists_directory(Dir2)->
	 make_directory(Dir2);true),
    decode_sections(File,Dir2),
    format('Calling souffle~n',[]),
    call_souffle(Dir2),
    (option(no_print)->
	 true
     ;
     format('Collecting results and printing~n',[]),
     collect_results(Dir2,_Results),
     generate_hints(Dir),
     pretty_print_results,
     print_stats
    ).

:-dynamic option/1.


save_option(Arg):-
    valid_option(Arg),
    assert(option(Arg)).

decode_sections(File,Dir):-
    sections(Sections),
    data_sections(Data_sections),
    foldl(collect_section_args(' --sect '),Sections,[],Sect_args),
    foldl(collect_section_args(' --data_sect '),Data_sections,[],Data_sect_args),
    atomic_list_concat(Sect_args,Section_chain),
    atomic_list_concat(Data_sect_args,Data_section_chain),
    atomic_list_concat(['./souffle_disasm ',' --file ',File,
			' --dir ',Dir,'/',Section_chain,Data_section_chain],Cmd),
    format('cmd: ~p~n',[Cmd]),
    shell(Cmd).

collect_section_args(Arg,Name,Acc_sec,Acc_sec2):-
    Acc_sec2=[Arg,Name|Acc_sec].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
call_souffle(Dir):-
    %souffle souffle_rules.pl -I ../examples/bzip/
    atomic_list_concat(['souffle ../src/souffle_rules.dl  -F ',Dir,' -D ',Dir,' -p ',Dir,'/profile'],Cmd),
    time(shell(Cmd)).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Pretty printer
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
result_descriptors([
			  res(section,3,'.facts'),
			  res(instruction,6,'.facts'),
			  res(op_regdirect,2,'.facts'),
			  res(op_immediate,2,'.facts'),
			  res(op_indirect,8,'.facts'),
			  res(data_byte,2,'.facts'),

			  res(direct_jump,2,'.csv'),	
			  res(reg_jump,1,'.csv'),
			  res(indirect_jump,1,'.csv'),
			  res(pc_relative_jump,2,'.csv'),

			  res(plt_call,2,'.csv'),

			  res(direct_call,2,'.csv'),

			  %res(possible_target,'phase2-possible_target',1,'.csv'),
			  res(likely_ea,'likely_ea_final',2,'.csv'),
			  res(remaining_ea,'phase2-remaining_ea',1,'.csv'),
			  res(function_symbol,2,'.csv'),
			  res(chunk_start,1,'.csv'),
			  res(chunk_overlap,'chunk_overlap2',2,'.csv'),
			  res(discarded_chunk,1,'.csv'),

			  res(symbolic_operand,2,'.csv'),
			  res(data_label,1,'.csv'),
			  res(float_data,1,'.csv'),
			  res(pointer_array,2,'.csv'),
			  res(pointer_array_element,3,'.csv'),
			  res(string,2,'.csv')
			  
			%  res(op_points_to_data,3,'.csv')
			 

		      ]).

:-dynamic section/3.
:-dynamic instruction/6.
:-dynamic op_regdirect/2.
:-dynamic op_immediate/2.
:-dynamic op_indirect/8.
:-dynamic data_byte/2.


:-dynamic direct_jump/2.
:-dynamic reg_jump/1.
:-dynamic indirect_jump/1.
:-dynamic pc_relative_jump/2.
:-dynamic plt_call/2.

:-dynamic direct_call/2.

:-dynamic likely_ea/2.
:-dynamic remaining_ea/1.
:-dynamic function_symbol/2.

:-dynamic chunk_start/1.
:-dynamic chunk_overlap/2.
:-dynamic discarded_chunk/1.

:-dynamic symbolic_operand/2.
:-dynamic data_label/1.
:-dynamic float_data/1.
:-dynamic pointer_array/2.
:-dynamic pointer_array_element/3.
:-dynamic string/2.

% :-dynamic op_points_to_data/3.

collect_results(Dir,results(Results)):-
    result_descriptors(Descriptors),
    maplist(collect_result(Dir),Descriptors,Results).

collect_result(Dir,res(Name,Filename,Arity,Ending),Result):-
    atom_concat(Filename,Ending,Name_file),
    directory_file_path(Dir,Name_file,Path),
    csv_read_file(Path, Result, [functor(Name), arity(Arity),separator(0'\t)]),
    maplist(assertz,Result).

collect_result(Dir,res(Name,Arity,Ending),Result):-
    atom_concat(Name,Ending,Name_file),
    directory_file_path(Dir,Name_file,Path),
    csv_read_file(Path, Result, [functor(Name), arity(Arity),separator(0'\t)]),
    maplist(assertz,Result).


get_op(0,none):-!.
get_op(N,reg(Name)):-
    op_regdirect(N,Name),!.
get_op(N,immediate(Immediate)):-
    op_immediate(N,Immediate),!.
get_op(N,indirect(Reg1,Reg2,Reg3,A,B,C,Size)):-
    op_indirect(N,Reg1,Reg2,Reg3,A,B,C,Size),!.

pretty_print_results:-
    print_header,
    get_chunks(Chunks),
    maplist(pp_chunk, Chunks),
    get_data(Data),
    maplist(pp_data,Data).

print_header:-
    option('-asm'),!,
    format('
	.intel_syntax noprefix
	.globl	main
	.type	main, @function~n',[]).
print_header.

get_data(Data):-
    findall(Data_byte,
	    (data_byte(EA,Content),
	     Data_byte=data_byte(EA,Content)
	     ),Data).


pp_data(data_byte(EA,Content)):-
    print_section_header(EA),
    findall(Comment,data_comment(EA,Comment),Comments),
    print_data_label(EA),
     (option('-asm')->
	 format('             .byte 0x~16R',[Content])
     ;
     format('         ~16R:   .byte 0x~16R',[EA,Content])
     ),
    print_comments(Comments),
    nl.

print_data_label(EA):-
    data_label(EA),!,
    format('L_~16R:~n',[EA]).

print_data_label(_EA).

data_comment(EA,float):-
    float_data(EA).

data_comment(EA,pointer(V)):-
    pointer_array(EA,Val),
    format(atom(V),'~16R',[Val]).

data_comment(EA,pointer_elem(Index,V)):-
    pointer_array_element(EA,Val,Beg),
    Index is (EA-Beg)/8,
    format(atom(V),'~16R',[Val]).

data_comment(EA,string(Size,String)):-
    string(EA,End),
    get_codes(EA,End,Codes),
    atom_codes(String,Codes),
    Size is End-EA.

get_codes(E,E,[]).
get_codes(B,E,[Code|Codes]):-
    data_byte(B,Code),
    B2 is B+1,
    get_codes(B2,E,Codes).

get_chunks(Chunks):-
    findall(Chunk,chunk_start(Chunk),Chunk_addresses),
    findall(Instruction,
	    (instruction(EA,Size,Name,Opc1,Opc2,Opc3),
	    \+likely_ea(EA,_),
	    remaining_ea(EA),
	    get_op(Opc1,Op1),
	    get_op(Opc2,Op2),
	    get_op(Opc3,Op3),
	    Instruction=instruction(EA,Size,Name,Op1,Op2,Op3)
	    ),Single_instructions),
     empty_assoc(Empty),
     foldl(get_chunk_content,Chunk_addresses,Empty,Map),
     foldl(accum_instruction,Single_instructions,Map,Map2),
     assoc_to_list(Map2,Chunks).

get_chunk_content(Chunk_addr,Assoc,Assoc1):-
    findall(Instruction,
	    (likely_ea(EA,Chunk_addr),
	     instruction(EA,Size,Name,Opc1,Opc2,Opc3),	     
	     get_op(Opc1,Op1),
	     get_op(Opc2,Op2),
	     get_op(Opc3,Op3),
	     Instruction=instruction(EA,Size,Name,Op1,Op2,Op3)
	    ),Instructions),
    put_assoc(Chunk_addr,Assoc,chunk(Instructions),Assoc1).


accum_instruction(instruction(EA,Size,OpCode,Op1,Op2,Op3),Assoc,Assoc1):-
    put_assoc(EA,Assoc,instruction(EA,Size,OpCode,Op1,Op2,Op3),Assoc1).


pp_chunk(EA_chunk-chunk(List)):-
    !,
    get_chunk_comments(EA_chunk,Comments),
    ((discarded_chunk(EA_chunk),\+option('-debug'))->
	 true
     ;
     print_section_header(EA_chunk),
    
     (is_function(EA_chunk,Name)->
	  print_function_header(Name)
      ;
      true
     ),!,
     format('~n  L_~16R:',[EA_chunk]) ,
     print_comments(Comments),nl,
     maplist(pp_instruction,List),nl
    ).

pp_chunk(_EA_chunk-Instruction):-
    (option('-debug')->
	 pp_instruction(Instruction)
     ;	 
     true
    ).



print_section_header(EA):-
    section('.text',_,EA),!,
    format('~n~n#=================================== ~n',[]),
    format('.text~n',[]),
    format('#=================================== ~n~n',[]).

print_section_header(EA):-
    section(Section_name,_,EA),!,
    format('~n~n#=================================== ~n',[]),
    format('.section ~p~n',[Section_name]),
    format('#=================================== ~n~n',[]).
print_section_header(_).

is_function(EA,Name):-
    function_symbol(EA,Name).
is_function(EA,'unkown'):-
      direct_call(_,EA).

print_function_header(Name):-
    	 format('#----------------------------------- ~n',[]),
	 format('~p:~n',[Name]),
	 format('#----------------------------------- ~n',[]).
		
get_chunk_comments(EA_chunk,Comments):-
	setof(Comment,chunk_comment(EA_chunk,Comment),Comments),!.
get_chunk_comments(_EA_chunk,[]).
    
chunk_comment(EA,discarded):-
    discarded_chunk(EA).

chunk_comment(EA,overlap_with(Str_EA2)):-
    chunk_overlap(EA2,EA),
    format(string(Str_EA2),'~16R',[EA2]).

chunk_comment(EA,overlap_with(Str_EA2)):-
    chunk_overlap(EA,EA2),
    format(string(Str_EA2),'~16R',[EA2]).

chunk_comment(EA,is_called):-
    direct_call(_,EA).

chunk_comment(EA,jumped_from(Str_or)):-
    direct_jump(Or,EA),
    format(string(Str_or),'~16R',[Or]).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

pp_instruction(instruction(EA,_,'CALL',_Op1,_,_)):-
    plt_call(EA,Dest),!,
    downcase_atom('CALL',OpCode_l),
    (option('-asm')->
	 format('             ~p ~p~n',[OpCode_l,Dest])
     ;
     format('         ~16R:   ~p ~p~n',[EA,OpCode_l,Dest])
    ).
pp_instruction(instruction(EA,_Size,OpCode,Op1,Op2,Op3)):-
    exclude(is_none,[Op1,Op2,Op3],Ops),
    get_ea_comments(EA,Comments),
    (member(symbolic_ops(Sym_ops),Comments)->true;Sym_ops=[]),
  
    pp_op_list(Ops,1,EA,Sym_ops,[],Pretty_ops_rev),

    %useful info
    convlist(get_comment,Ops,Op_comments),
   
    append(Comments,Op_comments,All_comments),
    downcase_atom(OpCode,OpCode_l),
    (option('-asm')->
	 format('             ~p',[OpCode_l])
     ;
     format('         ~16R:   ~p',[EA,OpCode_l])
    ),
   
    print_with_sep(Pretty_ops_rev,','),
    % print the names of the immediates if they are functions
    print_comments(All_comments),
    nl.

pp_instruction(_).

is_none(none).

print_comments(Comments):-
    (Comments\=[]->
	 format('          # ',[]),
	 maplist(print_with_space,Comments)
     ;true
    ).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
pp_op_list([],_N,_,_Sym_ops,Pretty_ops_rev,Pretty_ops_rev).

pp_op_list([Op|Ops],N,EA,Sym_ops,Accum,Pretty_ops_rev):-
    (member(N,Sym_ops)->
	 pp_op(Op,symbolic,EA,Op_pretty)
     ;
     pp_op(Op,normal,EA,Op_pretty)
    ),
    N1 is N+1,
    pp_op_list(Ops,N1,EA,Sym_ops,[Op_pretty|Accum],Pretty_ops_rev).

pp_op(reg(Name),_,_,Name).
pp_op(immediate(Num),normal,_,Num).
pp_op(immediate(Num),symbolic,_,Num_hex):-
    format(string(Num_hex),'L_~16R',[Num]).

    
pp_op(indirect('NullSReg',Reg,'NullReg64',1,0,_,_),_,_,[Reg]).

% special case for rip relative addressing
pp_op(indirect('NullSReg','RIP','NullReg64',1,Offset,_,Size),symbolic,EA,PP):-
    !,
    get_size_name(Size,Name),
    instruction(EA,Size_instr,_,_,_,_),
    Address is EA+Offset+Size_instr,
    format(atom(PP),'~p [L_~16R]',[Name,Address]).

pp_op(indirect('NullSReg',Reg,'NullReg64',1,Offset,_,Size),SymOrNormal,_,PP):-
    get_offset_and_sign(Offset,SymOrNormal,Offset1,PosNeg),
    get_size_name(Size,Name),
     Term=..[PosNeg,Reg,Offset1],
    format(atom(PP),'~p ~p',[Name,[Term]]).

pp_op(indirect('NullSReg','NullReg64',Reg_index,Mult,Offset,_,Size),SymOrNormal,_,PP):-
     get_offset_and_sign(Offset,SymOrNormal,Offset1,PosNeg),
     get_size_name(Size,Name),
     Term=..[PosNeg,Offset1,Reg_index*Mult],
     format(atom(PP),'~p ~p',[Name,[Term]]).
    

pp_op(indirect('NullSReg',Reg,Reg_index,Mult,0,_,Size),_SymOrNormal,_,PP):-
    get_size_name(Size,Name),
    format(atom(PP),'~p ~p',[Name,[Reg+Reg_index*Mult]]).


pp_op(indirect('NullSReg',Reg,Reg_index,Mult,Offset,_,Size),SymOrNormal,_,PP):-
    get_size_name(Size,Name),
    get_offset_and_sign(Offset,SymOrNormal,Offset1,PosNeg),
    Term=..[PosNeg,Offset1,Reg+Reg_index*Mult],
    format(atom(PP),'~p ~p',[Name,[Term]]).

%    format(string(Offset_hex),'~16R',[Offset]).

%FIXME 
pp_op(indirect(SReg,'NullReg64','NullReg64',1,Offset,_,Size),_SymOrNormal,_,PP):-
    get_size_name(Size,Name),
    format(atom(PP),'~p ~p',[Name,[SReg:Offset]]).

    %    format(string(Offset_hex),'~16R',[Offset]).
    


get_offset_and_sign(Offset,symbolic,Offset1,'+'):-
    format(atom(Offset1),'L_~16R',[Offset]).
get_offset_and_sign(Offset,normal,Offset1,'-'):-
    Offset<0,!,
    Offset1 is 0-Offset.
get_offset_and_sign(Offset,normal,Offset,'+').

get_size_name(128,'').
get_size_name(64,'QWORD PTR').
get_size_name(32,'DWORD PTR').
get_size_name(16,'WORD PTR').
get_size_name(8,'BYTE PTR').
get_size_name(Other,size(Other)).

%%%%%%%%%%%%%%%%%%%
% comments on instructions based on ea

get_ea_comments(EA,Comments):-
    setof(Comment,
	  ea_comment(EA,Comment),
	  Comments),!.
get_ea_comments(_EA,[]).

ea_comment(EA,not_in_chunk):-
\+likely_ea(EA,_).

ea_comment(EA,symbolic_ops(Symbolic_ops)):-
    findall(Op_num,symbolic_operand(EA,Op_num),Symbolic_ops),
    Symbolic_ops\=[].


ea_comment(EA,reg_jump):-
    reg_jump(EA).
ea_comment(EA,indirect_jump):-
    indirect_jump(EA).

ea_comment(EA,plt(Dest)):-
    plt_call(EA,Dest).


ea_comment(EA,pc_relative_jump(Dest_hex)):-
    pc_relative_jump(EA,Dest),
     format(atom(Dest_hex),'~16R',[Dest]).



%%%%%%%%%%%%%%%%%%%
% comments on instructions based on the operators

get_comment(Op,Name):-
    Op=immediate(Num),
    Num\=0,
    function_symbol(Num,Name).

	 
%%%%%%%%%%%%%%%%%%%%


print_stats:-
    format('~n~n;Result statistics:~n',[]),
    result_descriptors(Descriptors),
    maplist(print_descriptor_stats,Descriptors).

print_descriptor_stats(Res):-
    (Res=res(Name,Arity,_)
     ;
     Res=res(Name,_,Arity,_)
    ),
    functor(Head,Name,Arity),
    findall(Head,Head,Results),
    length(Results,N),
    format(' ; Number of ~p: ~p~n',[Name,N]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
generate_hints(Dir):-
    option('-hints'),!,
    findall(Code_ea,
	    (
		likely_ea(Code_ea,Chunk),
		chunk_start(Chunk),
		\+discarded_chunk(Chunk)

	    ),Code_eas),
    directory_file_path(Dir,'hints',Path),
    open(Path,write,S),
    maplist(print_code_ea(S),Code_eas),
      findall(Data_ea,
	    (
		(data_label(Data_ea); pointer_array_element(Data_ea,_,_))

	    ),Data_eas),
    maplist(print_data_ea(S),Data_eas),
    close(S).

generate_hints(_).    

print_code_ea(S,EA):-
    format(S,'0x~16R C',[EA]),
    instruction(EA,_,_,Op1,Op2,Op3),
    exclude(is_zero,[Op1,Op2,Op3],Non_zero_ops),
    length(Non_zero_ops,N_ops),
    findall(Index,symbolic_operand(EA,Index),Indexes),
    transform_indexes(Indexes,N_ops,Indexes_tr),
    maplist(print_sym_index(S),Indexes_tr),
    format(S,'~n',[]).

is_zero(0).
print_data_ea(S,EA):-
    format(S,'0x~16R D~n',[EA]).

transform_indexes(Indexes,N_ops,Indexes_tr):-
    foldl(transform_index(N_ops),Indexes,[],Indexes_tr).

transform_index(N_ops,Index,Accum,[Index_tr|Accum]):-
    Index_tr is N_ops-Index.
 
print_sym_index(S,I):-
      	 format(S,'so~p@0',[I]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% auxiliary predicates
hex_to_dec(Hex,Dec):-
    hex_bytes(Hex,Bytes),
    byte_list_to_num(Bytes,0,Dec).

byte_list_to_num([],Accum,Accum).
byte_list_to_num([Byte|Bytes],Accum,Dec):-
    Accum2 is Byte+256*Accum,
    byte_list_to_num(Bytes,Accum2,Dec).


print_with_space(Op):-
    format(' ~p ',[Op]).

print_with_sep([Last],_):-
    !,
    format(' ~p ',[Last]).
print_with_sep([X|Xs],Sep):-
    format(' ~p~p ',[X,Sep]),
    print_with_sep(Xs,Sep).
