! “ButterflyPACK” Copyright (c) 2018, The Regents of the University of California, through
! Lawrence Berkeley National Laboratory (subject to receipt of any required approvals from the
! U.S. Dept. of Energy). All rights reserved.

! If you have questions about your rights to use or distribute this software, please contact
! Berkeley Lab's Intellectual Property Office at  IPO@lbl.gov.

! NOTICE.  This Software was developed under funding from the U.S. Department of Energy and the
! U.S. Government consequently retains certain rights. As such, the U.S. Government has been
! granted for itself and others acting on its behalf a paid-up, nonexclusive, irrevocable
! worldwide license in the Software to reproduce, distribute copies to the public, prepare
! derivative works, and perform publicly and display publicly, and to permit other to do so.

! Developers: Yang Liu
!             (Lawrence Berkeley National Lab, Computational Research Division).

#include "ButterflyPACK_config.fi"
module Bplus_factor
use Bplus_randomizedop

contains


subroutine Full_LU(blocks,option,stats)

    implicit none

	type(Hoption)::option
	type(Hstat)::stats

    integer size_m, size_n
    integer i,j,k,ii,jj,kk
    real*8  T0,T1
    type(matrixblock) :: blocks
    real(kind=8) flop

    T0=OMP_get_wtime()
    size_m=size(blocks%fullmat,1)
    if(option%ILU==0)then
		! do ii=1,size_m
		! do jj=1,size_m
			! write(777,*)dble(blocks%fullmat(ii,jj)),aimag(blocks%fullmat(ii,jj))
		! enddo
		! enddo
		call getrff90(blocks%fullmat,blocks%ipiv,flop=flop)
		stats%Flop_Factor = stats%Flop_Factor + flop
		! do ii=1,size_m
		! do jj=1,size_m
			! write(778,*)dble(blocks%fullmat(ii,jj)),aimag(blocks%fullmat(ii,jj))
		! enddo
		! enddo
	else
		do ii=1,size_m
			blocks%ipiv(ii)=ii
		enddo
	endif
	T1=OMP_get_wtime()
    stats%Time_Direct_LU=stats%Time_Direct_LU+T1-T0

    return

end subroutine Full_LU


subroutine Full_add_multiply(block3,chara,block1,block2,h_mat,option,stats,ptree,msh)

    implicit none

	type(Hoption)::option
	type(Hstat)::stats
	type(Hmat)::h_mat
	type(proctree)::ptree
	type(mesh)::msh

    integer level_butterfly, flag
    integer i, j, k, ii, level, mm, nn, kk, rank, level_blocks, mn, group_k
    integer style(3), data_type(3), id1, id2, id3
    character chara
    DT,allocatable::Vin(:,:),Vin1(:,:),fullmat(:,:),fullmatrix(:,:)
    real*8 T0, T1
    type(matrixblock) :: block1, block2, block3

	stats%Flop_Tmp=0

	T0=OMP_get_wtime()
    style(3)=block3%style
    level_blocks=block3%level

	group_k = block1%col_group
	kk=msh%basis_group(group_k)%tail-msh%basis_group(group_k)%head+1

	call assert(style(3)==1,'block3 supposed to be style 1')

	mm=size(block3%fullmat,1)
    nn=size(block3%fullmat,2)

	allocate(Vin(nn,nn))
	Vin = 0d0
	do ii=1,nn
		Vin(ii,ii)=1d0
	enddo
	allocate(Vin1(kk,nn))
	Vin1 = 0d0
	allocate(fullmatrix(mm,nn))
	fullmatrix=0d0

	call Hmat_block_MVP_dat(block2,'N',msh%basis_group(block2%row_group)%head,msh%basis_group(block2%col_group)%head,nn,Vin,Vin1,cone,ptree,stats)
	call Hmat_block_MVP_dat(block1,'N',msh%basis_group(block1%row_group)%head,msh%basis_group(block1%col_group)%head,nn,Vin1,fullmatrix,cone,ptree,stats)

	if (chara=='-')fullmatrix = -fullmatrix
	block3%fullmat = block3%fullmat + fullmatrix
	deallocate(fullmatrix)
	deallocate(Vin)
	deallocate(Vin1)


    T1=OMP_get_wtime()
    stats%Time_Add_Multiply=stats%Time_Add_Multiply+T1-T0
    stats%Flop_Factor = stats%Flop_Factor+stats%Flop_Tmp

    return

end subroutine Full_add_multiply

subroutine Full_add(block3,chara,block1,ptree,stats)

    implicit none

    integer level_butterfly, flag,group_n,group_m
    integer i, j, k, level, mm, nn, rank, level_blocks, mn, ii, jj
    integer style(3), data_type(3), id1, id2, id3
    character chara
    DT,allocatable:: Vin(:,:)
    !logical isNaN
    real*8 T0, T1
    type(matrixblock) :: block1, block3
	type(Hstat):: stats
	type(proctree):: ptree
    DT,allocatable::fullmatrix(:,:)

	stats%Flop_Tmp=0

    style(3)=block3%style
    style(1)=block1%style
    level_blocks=block3%level


    T0=OMP_get_wtime()
    call assert(style(1)/=1,'block1 not supposed to be full')
    call assert(style(3)==1,'block3 supposed to be full')

	group_m = block3%row_group
	group_n = block3%col_group

	mm=block3%M
	nn=block3%N
	allocate(Vin(nn,nn))

	Vin = 0d0
	do ii=1,nn
		Vin(ii,ii)=1d0
	enddo

	allocate(fullmatrix(mm,nn))
	fullmatrix=0d0

	call BF_block_MVP_dat(block1,'N',mm,nn,nn,Vin,fullmatrix,cone,czero,ptree,stats)

	if (chara=='-')fullmatrix = -fullmatrix

	block3%fullmat = block3%fullmat + fullmatrix
	deallocate(fullmatrix)
	deallocate(Vin)


    T1=OMP_get_wtime()
    stats%Time_Add_Multiply=stats%Time_Add_Multiply+T1-T0
    stats%Flop_Factor = stats%Flop_Factor+stats%Flop_Tmp
    return

end subroutine Full_add


subroutine LR_minusBC(ho_bf1,level_c,rowblock,ptree,stats)

    use BPACK_DEFS

	use MISC_Utilities
    implicit none

	integer level_c,rowblock
    integer i,j,k,level,num_blocks,num_row,num_col,ii,jj,kk,test
    integer mm,nn,mn,blocks1,blocks2,blocks3,level_butterfly,groupm_diag
    character chara
    real(kind=8) a,b,c,d
    DT ctemp1, ctemp2
	type(matrixblock),pointer::block_o

    ! type(vectorsblock), pointer :: random1, random2

    real(kind=8),allocatable :: Singular(:)
	integer idx_start_glo,N_diag,idx_start_diag,idx_start_loc,idx_end_loc
	! DT,allocatable::vec_old(:,:),vec_new(:,:),matrixtemp1(:,:),myA(:,:),BUold(:,:),BVold(:,:),CUold(:,:),CVold(:,:),BU(:,:),BV(:,:),CU(:,:),CV(:,:),BVCU(:,:),BUBVCU(:,:)

	integer Nsub,Ng,unique_nth,level_left_start,ll
	integer*8 idx_start
    integer level_blocks
    integer groupm_start, groupn_start,dimension_rank,rank1,rank
    integer header_mm, header_nn
	integer header_m, header_n, tailer_m, tailer_n

	real(kind=8)::n2,n1
	type(hobf)::ho_bf1
	type(matrixblock),pointer::block_off1,block_off2
	type(proctree)::ptree
	integer pgno,pgno1,pgno2
	integer descBUold(9),descBVold(9),descCUold(9),descCVold(9), descBU(9),descBV(9),descCU(9),descCV(9),descBVCU(9),descBUBVCU(9)
	integer ctxt1,ctxt2,ctxt,ctxtall,info,myrow,mycol,myArows,myAcols
	type(Hstat)::stats

	ctemp1=1.0d0 ; ctemp2=0.0d0
	block_off1 => ho_bf1%levels(level_c)%BP_inverse_update(rowblock*2-1)%LL(1)%matrices_block(1)
	block_off2 => ho_bf1%levels(level_c)%BP_inverse_update(rowblock*2)%LL(1)%matrices_block(1)

	block_o =>  ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%LL(1)%matrices_block(1)
	call BF_delete(block_o,1)

	block_o%level_butterfly = 0
	block_o%ButterflyU%nblk_loc=1
	block_o%ButterflyU%inc=1
	block_o%ButterflyU%idx=1
	block_o%ButterflyV%nblk_loc=1
	block_o%ButterflyV%inc=1
	block_o%ButterflyV%idx=1


	allocate(block_o%ButterflyU%blocks(1))
	allocate(block_o%ButterflyV%blocks(1))

	pgno = block_o%pgno
	pgno1 = block_off1%pgno
	pgno2 = block_off2%pgno
	! if(ptree%MyID==2)write(*,*)pgno,pgno1,pgno2,'nana'
	call assert(pgno==pgno1,'block_o and block_off1 should be on the same process group')
	call assert(pgno==pgno2,'block_o and block_off2 should be on the same process group')

	mm = block_off1%M
	nn = block_off1%N

	rank = block_off2%rankmax
	block_o%rankmax=rank
	block_o%M_loc = block_off1%M_loc
	block_o%N_loc = block_o%M_loc
	allocate(block_o%M_p(size(block_off1%M_p,1),2))
	block_o%M_p = block_off1%M_p
	allocate(block_o%N_p(size(block_off1%M_p,1),2))
	block_o%N_p = block_off1%M_p

	allocate(block_o%ButterflyU%blocks(1)%matrix(block_o%M_loc,rank))
	block_o%ButterflyU%blocks(1)%matrix =0
	allocate(block_o%ButterflyV%blocks(1)%matrix(block_o%M_loc,rank))
	block_o%ButterflyV%blocks(1)%matrix =block_off2%ButterflyV%blocks(1)%matrix

	stats%Flop_Tmp=0
	call BF_block_MVP_dat(block_off1,'N',block_off1%M_loc,block_off1%N_loc,rank,block_off2%ButterflyU%blocks(1)%matrix,block_o%ButterflyU%blocks(1)%matrix,ctemp1,ctemp2,ptree,stats)
	block_o%ButterflyU%blocks(1)%matrix = -block_o%ButterflyU%blocks(1)%matrix
	! if(ptree%MyID==2)write(*,*)pgno,pgno1,pgno2,'neeeeana'
	stats%Flop_Factor = stats%Flop_Factor + stats%Flop_Tmp
	stats%Flop_Tmp=0

    return

end subroutine LR_minusBC


subroutine LR_SMW(block_o,Memory,ptree,stats,pgno)

    use BPACK_DEFS


    implicit none

    integer level_c,rowblock,kover,rank,kk1,kk2,nprow,npcol
	integer i,j,k,level,num_blocks,blocks3,num_row,num_col,ii,jj,kk,level_butterfly, mm, nn
    integer dimension_rank, dimension_m, dimension_n, blocks, groupm, groupn,index_j,index_i
    real(kind=8) a,b,c,d,Memory,flop
    DT ctemp,TEMP(1)
	type(matrixblock)::block_o
	DT, allocatable::matrixtemp(:,:),matrixtemp1(:,:),matrixtemp2(:,:),matrixtemp3(:,:),UU(:,:),VV(:,:),matrix_small(:,:),vin(:,:),vout1(:,:),vout2(:,:),vout3(:,:),matU(:,:)
	real(kind=8), allocatable:: Singular(:)
    integer, allocatable :: ipiv(:),iwork(:)
	type(proctree)::ptree
	integer pgno,ctxt,ctxt_head,myrow,mycol,myArows,myAcols,iproc,myi,jproc,myj,info
	integer descUV(9),descsmall(9),desctemp(9),TEMPI(1)

	integer lwork,liwork,lcmrc,ierr
	DT,allocatable:: work(:)
	type(Hstat)::stats

	ctxt = ptree%pgrp(pgno)%ctxt
	ctxt_head = ptree%pgrp(pgno)%ctxt_head

	rank = size(block_o%ButterflyU%blocks(1)%matrix,2)
	allocate(matrixtemp(rank,rank))
	matrixtemp=0
	allocate(matrixtemp1(rank,rank))
	matrixtemp1=0
	allocate(matU(block_o%M_loc,rank))
	matU = block_o%ButterflyU%blocks(1)%matrix

	! write(*,*)fnorm(block_o%ButterflyV%blocks(1)%matrix,size(block_o%ButterflyV%blocks(1)%matrix,1),size(block_o%ButterflyV%blocks(1)%matrix,2)),fnorm(block_o%ButterflyU%blocks(1)%matrix,size(block_o%ButterflyU%blocks(1)%matrix,1),size(block_o%ButterflyU%blocks(1)%matrix,2)),ptree%MyID,'re',shape(block_o%ButterflyV%blocks(1)%matrix),shape(block_o%ButterflyU%blocks(1)%matrix),shape(matrixtemp),isnanMat(block_o%ButterflyV%blocks(1)%matrix,size(block_o%ButterflyV%blocks(1)%matrix,1),size(block_o%ButterflyV%blocks(1)%matrix,2)),isnanMat(block_o%ButterflyU%blocks(1)%matrix,size(block_o%ButterflyU%blocks(1)%matrix,1),size(block_o%ButterflyU%blocks(1)%matrix,2))

	call gemmf90(block_o%ButterflyV%blocks(1)%matrix,block_o%M_loc,block_o%ButterflyU%blocks(1)%matrix,block_o%M_loc,matrixtemp,rank,'T','N',rank,rank,block_o%M_loc,cone,czero,flop=flop)
	stats%Flop_Factor = stats%Flop_Factor + flop

	! write(*,*)'goog1'
	call assert(MPI_COMM_NULL/=ptree%pgrp(pgno)%Comm,'communicator should not be null 1')
	call MPI_ALLREDUCE(matrixtemp,matrixtemp1,rank*rank,MPI_DT,MPI_SUM,ptree%pgrp(pgno)%Comm,ierr)
	! write(*,*)'goog2'
	do ii=1,rank
		matrixtemp1(ii,ii) = matrixtemp1(ii,ii)+1
	enddo

	! write(*,*)abs(matrixtemp1),rank,'gggddd'

	if(rank<=nbslpk)then

#if 0
		allocate(ipiv(rank))
		ipiv=0
		call getrff90(matrixtemp1,ipiv,flop=flop)
		stats%Flop_Factor = stats%Flop_Factor + flop
		call getrif90(matrixtemp1,ipiv,flop=flop)
		stats%Flop_Factor = stats%Flop_Factor + flop
		deallocate(ipiv)
#else
		matrixtemp = matrixtemp1
		call GeneralInverse(rank,rank,matrixtemp,matrixtemp1,SafeEps,Flops=flop)
		stats%Flop_Factor = stats%Flop_Factor + flop
#endif

	else

		!!!!!! the SVD-based pseudo inverse needs to be implemented later

		call blacs_gridinfo(ctxt, nprow, npcol, myrow, mycol)
		if(myrow/=-1 .and. mycol/=-1)then
			if(ptree%MyID==ptree%pgrp(pgno)%head)then
				call blacs_gridinfo(ctxt_head, nprow, npcol, myrow, mycol)
				myArows = numroc_wp(rank, nbslpk, myrow, 0, nprow)
				call descinit( desctemp, rank, rank, nbslpk, nbslpk, 0, 0, ctxt_head, max(myArows,1), info )
				call assert(info==0,'descinit fail for desctemp')
			else
				desctemp(2)=-1
			endif

			call blacs_gridinfo(ctxt, nprow, npcol, myrow, mycol)
			myArows = numroc_wp(rank, nbslpk, myrow, 0, nprow)
			myAcols = numroc_wp(rank, nbslpk, mycol, 0, npcol)

			allocate(matrix_small(myArows,myAcols))
			matrix_small=0

			call descinit( descsmall, rank, rank, nbslpk, nbslpk, 0, 0, ctxt, max(myArows,1), info )
			! if(info/=0)then
				! write(*,*)'nneref',rank,nbslpk,myArows,myAcols,max(myArows,1),ptree%pgrp(pgno)%nproc,ptree%MyID,ptree%pgrp(pgno)%head,pgno,ptree%pgrp(pgno)%nprow,ptree%pgrp(pgno)%npcol,info
			! endif
			call assert(info==0,'descinit fail for descsmall')

			call pgemr2df90(rank, rank, matrixtemp1, 1, 1, desctemp, matrix_small, 1, 1, descsmall, ctxt)

			allocate(ipiv(myArows+nbslpk))
			ipiv=0
			call pgetrff90(rank,rank,matrix_small,1,1,descsmall,ipiv,info,flop=flop)
			stats%Flop_Factor = stats%Flop_Factor + flop/dble(nprow*npcol)

			call pgetrif90(rank,matrix_small,1,1,descsmall,ipiv,flop=flop)
			stats%Flop_Factor = stats%Flop_Factor + flop/dble(nprow*npcol)

			deallocate(ipiv)


			call pgemr2df90(rank, rank, matrix_small, 1, 1, descsmall,matrixtemp1, 1, 1, desctemp, ctxt)
			deallocate(matrix_small)
		endif

		call MPI_Bcast(matrixtemp1,rank*rank,MPI_DT,0,ptree%pgrp(pgno)%Comm,ierr)

	endif


	call gemmf90(matU,block_o%M_loc,matrixtemp1,rank,block_o%ButterflyU%blocks(1)%matrix,block_o%M_loc,'N','N',block_o%M_loc,rank,rank,cone,czero,flop=flop)
	block_o%ButterflyU%blocks(1)%matrix = -block_o%ButterflyU%blocks(1)%matrix
	stats%Flop_Factor = stats%Flop_Factor + flop

	deallocate(matrixtemp,matrixtemp1,matU)



	Memory = 0
	Memory = Memory + SIZEOF(block_o%ButterflyV%blocks(1)%matrix)/1024.0d3
	Memory = Memory + SIZEOF(block_o%ButterflyU%blocks(1)%matrix)/1024.0d3

    return

end subroutine LR_SMW



subroutine LR_Sblock(ho_bf1,level_c,rowblock,ptree,stats)

    use BPACK_DEFS

	use MISC_Utilities
    implicit none

	integer level_c,rowblock
    integer i,j,k,level,num_blocks,num_row,num_col,ii,jj,kk,test,pp,qq
    integer mm,nn,mn,blocks1,blocks2,blocks3,level_butterfly,groupm,groupn,groupm_diag
    character chara
    real(kind=8) a,b,c,d
	type(matrixblock),pointer::block_o,blocks

    type(vectorsblock), pointer :: random1, random2

    real(kind=8),allocatable :: Singular(:)
	integer idx_start_glo,N_diag,idx_start_diag,idx_end_diag,idx_start_loc,idx_end_loc
	DT,allocatable::vec_old(:,:),vec_new(:,:)

	integer Nsub,Ng,unique_nth,level_left_start
	integer*8 idx_start
    integer level_blocks,head,tail
    integer groupm_start, groupn_start,dimension_rank
    integer header_mm, header_nn
	integer header_m, header_n, tailer_m, tailer_n

	integer nth_s,nth_e,num_vect_sub,nth
	real(kind=8)::n2,n1
	type(hobf)::ho_bf1
	type(proctree)::ptree
	type(Hstat)::stats



	block_o =>  ho_bf1%levels(level_c)%BP_inverse_update(rowblock)%LL(1)%matrices_block(1)

	! write(*,*)block_o%row_group,block_o%col_group,isnanMat(block_o%ButterflyU%blocks(1)%matrix,size(block_o%ButterflyU%blocks(1)%matrix,1),size(block_o%ButterflyU%blocks(1)%matrix,2)),'dfdU1',ptree%MyID
	! write(*,*)block_o%row_group,block_o%col_group,isnanMat(block_o%ButterflyV%blocks(1)%matrix,size(block_o%ButterflyV%blocks(1)%matrix,1),size(block_o%ButterflyV%blocks(1)%matrix,2)),'dfdV1',ptree%MyID

    level_butterfly=block_o%level_butterfly
    call assert(level_butterfly==0,'Butterfly_Sblock_LowRank only works with LowRank blocks')



	num_blocks=2**level_butterfly


	num_vect_sub = size(block_o%ButterflyU%blocks(1)%matrix,2)
    ! groupm=block_o%row_group  ! Note: row_group and col_group interchanged here

	! get the right multiplied vectors
	pp = ptree%myid-ptree%pgrp(block_o%pgno)%head+1
	idx_start_glo = block_o%headm + block_o%M_p(pp,1) -1



	! mm=block_o%M
	mm=block_o%M_loc
	allocate(vec_old(mm,num_vect_sub))
	allocate(vec_new(mm,num_vect_sub))
	vec_old = block_o%ButterflyU%blocks(1)%matrix
	stats%Flop_Tmp=0
	do level = ho_bf1%Maxlevel+1,level_c+1,-1
		N_diag = 2**(level-level_c-1)
		idx_start_diag = max((rowblock-1)*N_diag+1,ho_bf1%levels(level)%Bidxs)
		idx_end_diag = min(rowblock*N_diag,ho_bf1%levels(level)%Bidxe)
		vec_new = 0

		n1 = OMP_get_wtime()
		do ii = idx_start_diag,idx_end_diag

			if(associated(ho_bf1%levels(level)%BP_inverse(ii)%LL))then
			blocks=>ho_bf1%levels(level)%BP_inverse(ii)%LL(1)%matrices_block(1)
			if(IOwnPgrp(ptree,blocks%pgno))then

			qq = ptree%myid-ptree%pgrp(blocks%pgno)%head+1
			head = blocks%headm + blocks%M_p(qq,1) -1
			tail = head + blocks%M_loc - 1
			idx_start_loc = head-idx_start_glo+1
			idx_end_loc = tail-idx_start_glo+1
			if(level==ho_bf1%Maxlevel+1)then
				call Full_block_MVP_dat(blocks,'N',idx_end_loc-idx_start_loc+1,num_vect_sub,&
				&vec_old(idx_start_loc:idx_end_loc,1:num_vect_sub),vec_new(idx_start_loc:idx_end_loc,1:num_vect_sub),cone,czero)
			else
				call BF_block_MVP_inverse_dat(ho_bf1,level,ii,'N',idx_end_loc-idx_start_loc+1,num_vect_sub,vec_old(idx_start_loc:idx_end_loc,1:num_vect_sub),vec_new(idx_start_loc:idx_end_loc,1:num_vect_sub),ptree,stats)
			endif

			endif
			endif
		end do
		n2 = OMP_get_wtime()
		! time_tmp = time_tmp + n2 - n1


		vec_old = vec_new
	end do
	! ! write(*,*)vec_new(1,1),RandomVectors_InOutput(2)%vector(1,1)
	block_o%ButterflyU%blocks(1)%matrix = vec_new
	! write(*,*)block_o%row_group,block_o%col_group,isnanMat(block_o%ButterflyU%blocks(1)%matrix,size(block_o%ButterflyU%blocks(1)%matrix,1),size(block_o%ButterflyU%blocks(1)%matrix,2)),'dfdU',ptree%MyID
	! write(*,*)block_o%row_group,block_o%col_group,isnanMat(block_o%ButterflyV%blocks(1)%matrix,size(block_o%ButterflyV%blocks(1)%matrix,1),size(block_o%ButterflyV%blocks(1)%matrix,2)),'dfdV',ptree%MyID
	deallocate(vec_old)
	deallocate(vec_new)

	stats%Flop_Factor = stats%Flop_Factor + stats%Flop_Tmp

    return

end subroutine LR_Sblock


subroutine BF_inverse_schur_partitionedinverse(ho_bf1,level_c,rowblock,error_inout,option,stats,ptree,msh)

    use BPACK_DEFS
	use MISC_Utilities


    use omp_lib

    implicit none

	integer level_c,rowblock
    integer blocks1, blocks2, blocks3, level_butterfly, i, j, k, num_blocks
    integer num_col, num_row, level, mm, nn, ii, jj,tt,ll
    character chara
    real(kind=8) T0
    type(matrixblock),pointer::block_o,block_off1,block_off2
    integer rank_new_max,rank0
	real(kind=8):: rank_new_avr,error
	integer niter
	real(kind=8):: error_inout,rate,err_avr
	integer itermax,ntry
	real(kind=8):: n1,n2,Memory
	type(Hoption)::option
	type(Hstat)::stats
	type(hobf)::ho_bf1
	type(proctree)::ptree
	type(mesh)::msh
	integer pgno

	error_inout=0

	block_off1 => ho_bf1%levels(level_c)%BP_inverse_update(rowblock*2-1)%LL(1)%matrices_block(1)
	block_off2 => ho_bf1%levels(level_c)%BP_inverse_update(rowblock*2)%LL(1)%matrices_block(1)


	block_o => ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%LL(1)%matrices_block(1)
	block_o%level_butterfly = block_off1%level_butterfly
	level_butterfly=block_o%level_butterfly

	Memory = 0

	if(block_off1%level_butterfly==0 .or. block_off2%level_butterfly==0)then
		call LR_minusBC(ho_bf1,level_c,rowblock,ptree,stats)
	else
		ho_bf1%ind_lv=level_c
		ho_bf1%ind_bk=rowblock
		rank0 = max(block_off1%rankmax,block_off2%rankmax)
		rate=1.2d0
		call BF_randomized(block_o%pgno,level_butterfly,rank0,rate,block_o,ho_bf1,BF_block_MVP_inverse_minusBC_dat,error,'minusBC',option,stats,ptree,msh)
		stats%Flop_Factor=stats%Flop_Factor+stats%Flop_Tmp
		error_inout = max(error_inout, error)
	endif

	pgno = block_o%pgno

	n1 = OMP_get_wtime()
	! if(block_o%level==3)then
	if(level_butterfly>=option%schulzlevel)then
		call BF_inverse_schulziteration_IplusButter(block_o,error,option,stats,ptree,msh)
	else
		call BF_inverse_partitionedinverse_IplusButter(block_o,level_butterfly,0,option,error,stats,ptree,msh,pgno)
	endif

	error_inout = max(error_inout, error)

	n2 = OMP_get_wtime()
	stats%Time_SMW=stats%Time_SMW + n2-n1
	! write(*,*)'I+B Inversion Time:',n2-n1

	if(ptree%MyID==Main_ID .and. option%verbosity>=1)write(*,'(A10,I5,A6,I3,A8,I3,A11,Es14.7)')'OneL No. ',rowblock,' rank:',block_o%rankmax,' L_butt:',block_o%level_butterfly,' error:',error_inout


    return

end subroutine BF_inverse_schur_partitionedinverse

subroutine BF_inverse_schulziteration_IplusButter(block_o,error_inout,option,stats,ptree,msh)

    use BPACK_DEFS
	use MISC_Utilities


    use omp_lib

    implicit none

	integer level_c,rowblock
    integer groupm,blocks1, blocks2, blocks3, level_butterfly, i, j, k, num_blocks
    integer num_col, num_row, level, mm, nn, ii, jj,tt,ll
    character chara
    real(kind=8) T0
    type(matrixblock)::block_o,block_Xn
    integer rank_new_max,rank0,num_vect
	real(kind=8):: rank_new_avr,error
	integer niter
	real(kind=8):: error_inout,rate,err_avr
	integer itermax,ntry,converged
	real(kind=8):: n1,n2,Memory,memory_temp,norm1,norm2
	type(Hoption)::option
	type(Hstat)::stats
	type(proctree)::ptree
	type(mesh)::msh
	type(schulz_operand)::schulz_op
	DT,allocatable::VecIn(:,:),VecOut(:,:),VecBuff(:,:)
	DT::ctemp1,ctemp2
	character(len=10)::iternumber
	integer ierr

	error_inout=0
	level_butterfly=block_o%level_butterfly

	Memory = 0

	mm = block_o%M_loc

	num_vect=1
	allocate(VecIn(mm,num_vect))
	VecIn=0
	allocate(VecOut(mm,num_vect))
	VecOut=0
	allocate(VecBuff(mm,num_vect))
	VecBuff=0

	call BF_copy('N',block_o,schulz_op%matrices_block,memory_temp)
	call BF_copy('N',block_o,block_Xn,memory_temp)


	call BF_compute_schulz_init(schulz_op,option,ptree,stats)


	itermax=100
	converged=0
	! n1 = OMP_get_wtime()
	do ii=1,itermax

		write(iternumber ,  "(I4)") ii

		rank0 = block_Xn%rankmax

		rate=1.2d0
		call BF_randomized(block_Xn%pgno,level_butterfly,rank0,rate,block_Xn,schulz_op,BF_block_MVP_schulz_dat,error,'schulz iter'//TRIM(iternumber),option,stats,ptree,msh,ii)
		stats%Flop_Factor=stats%Flop_Factor+stats%Flop_Tmp

		if(schulz_op%order==2)schulz_op%scale=schulz_op%scale*(2-schulz_op%scale)
		if(schulz_op%order==3)schulz_op%scale=schulz_op%scale*(3 - 3*schulz_op%scale + schulz_op%scale**2d0)

		! test error

		ctemp1=1.0d0 ; ctemp2=0.0d0
		call RandomMat(mm,num_vect,min(mm,num_vect),VecIn,1)
		! XnR
		call BF_block_MVP_schulz_Xn_dat(schulz_op,block_Xn,'N',mm,mm,num_vect,VecIn,VecBuff,ctemp1,ctemp2,ptree,stats,ii+1)


		! AXnR
		call BF_block_MVP_dat(schulz_op%matrices_block,'N',mm,mm,num_vect,VecBuff,VecOut,ctemp1,ctemp2,ptree,stats)
		VecOut = 	VecBuff+VecOut

		norm1 = fnorm(VecOut-VecIn,mm,num_vect)**2d0
		norm2 = fnorm(VecIn,mm,num_vect)**2d0
		call MPI_ALLREDUCE(MPI_IN_PLACE, norm1, 1,MPI_double_precision, MPI_SUM, ptree%pgrp(schulz_op%matrices_block%pgno)%Comm,ierr)
		call MPI_ALLREDUCE(MPI_IN_PLACE, norm2, 1,MPI_double_precision, MPI_SUM, ptree%pgrp(schulz_op%matrices_block%pgno)%Comm,ierr)
		error_inout = sqrt(norm1)/sqrt(norm2)


		if(ptree%MyID==Main_ID .and. option%verbosity>=1)write(*,'(A22,A6,I3,A8,I2,A8,I3,A7,Es14.7)')' Schultz ',' rank:',block_Xn%rankmax,' Iter:',ii,' L_butt:',block_Xn%level_butterfly,' error:',error_inout


		if(error_inout<option%tol_rand)then
			converged=1
			exit
		endif

		if(isnan(error_inout))then
			converged=0
			exit
		endif


	enddo
	! n2 = OMP_get_wtime()


	if(converged==0)then
		write(*,*)'Schulz Iteration does not converge'
		stop
	else
		! write(*,*)'Schulz Iteration Time:',n2-n1
		call BF_delete(block_o,1)
		call BF_get_rank(block_Xn,ptree)
		rank_new_max = block_Xn%rankmax
		call BF_copy_delete(block_Xn,block_o,Memory)
		call BF_delete(schulz_op%matrices_block,1)
		if(allocated(schulz_op%diags))deallocate(schulz_op%diags)
	endif

	deallocate(VecIn)
	deallocate(VecOut)
	deallocate(VecBuff)


    return

end subroutine BF_inverse_schulziteration_IplusButter







subroutine BF_compute_schulz_init(schulz_op,option,ptree,stats)

    use BPACK_DEFS
	use MISC_Utilities


    use omp_lib

    implicit none

    integer level_butterfly
    integer mm, nn, mn,ii
    real(kind=8) T0

	real(kind=8):: error
	integer niter,groupm,groupn
	real(kind=8):: error_inout
	integer num_vect,rank,ranktmp,q,qq
	real(kind=8):: n1,n2,memory_temp,flop
	type(Hoption)::option
	type(schulz_operand)::schulz_op
	real(kind=8), allocatable:: Singular(:)
	DT, allocatable::UU(:,:),VV(:,:),RandVectIn(:,:),RandVectOut(:,:),matrixtmp(:,:),matrixtmp1(:,:)
	type(proctree)::ptree
	type(Hstat)::stats

	stats%Flop_tmp=0

	schulz_op%order=option%schulzorder

	error_inout=0

	level_butterfly=schulz_op%matrices_block%level_butterfly

	mm = schulz_op%matrices_block%M_loc
	nn=mm
	num_vect=min(10,nn)

	allocate(RandVectIn(nn,num_vect))
	allocate(RandVectOut(mm,num_vect))
	RandVectOut=0
	call RandomMat(nn,num_vect,min(nn,num_vect),RandVectIn,1)

	! computation of AR
	call BF_block_MVP_dat(schulz_op%matrices_block,'N',mm,nn,num_vect,RandVectIn,RandVectOut,cone,czero,ptree,stats)
	RandVectOut = RandVectIn+RandVectOut


	! power iteration of order q, the following is prone to roundoff error, see algorithm 4.4 Halko 2010
	q=6
	do qq=1,q
		RandVectOut=conjg(cmplx(RandVectOut,kind=8))

		call BF_block_MVP_dat(schulz_op%matrices_block,'T',mm,nn,num_vect,RandVectOut,RandVectIn,cone,czero,ptree,stats)
		RandVectIn = RandVectOut+RandVectIn

		RandVectIn=conjg(cmplx(RandVectIn,kind=8))

		call BF_block_MVP_dat(schulz_op%matrices_block,'N',mm,nn,num_vect,RandVectIn,RandVectOut,cone,czero,ptree,stats)
		RandVectOut = RandVectIn+RandVectOut

	enddo



	! computation of range Q of AR
	call PComputeRange(schulz_op%matrices_block%M_p,num_vect,RandVectOut,ranktmp,option%tol_Rdetect,ptree,schulz_op%matrices_block%pgno,flop)
	stats%Flop_Tmp = stats%Flop_Tmp + flop


	! computation of B = Q^c*A
	RandVectOut=conjg(cmplx(RandVectOut,kind=8))
	call BF_block_MVP_dat(schulz_op%matrices_block,'T',mm,nn,num_vect,RandVectOut,RandVectIn,cone,czero,ptree,stats)
	RandVectIn =RandVectOut+RandVectIn
	RandVectOut=conjg(cmplx(RandVectOut,kind=8))

	! computation of singular values of B
	mn=min(schulz_op%matrices_block%M,ranktmp)
	allocate(Singular(mn))
	Singular=0
	call PSVDTruncateSigma(schulz_op%matrices_block,RandVectIn,ranktmp,rank,Singular,option,stats,ptree,flop)
	stats%Flop_Tmp = stats%Flop_Tmp + flop
	schulz_op%A2norm=Singular(1)
	deallocate(Singular)


	deallocate(RandVectIn)
	deallocate(RandVectOut)



	! allocate(matrixtmp1(nn,nn))
	! matrixtmp1=0
	! do ii=1,nn
		! matrixtmp1(ii,ii)=1d0
	! enddo
	! allocate(matrixtmp(nn,nn))
	! matrixtmp=0
	! call BF_block_MVP_dat(schulz_op%matrices_block,'N',mm,nn,nn,matrixtmp1,matrixtmp,cone,czero)
	! matrixtmp = matrixtmp+matrixtmp1
	! allocate (UU(nn,nn),VV(nn,nn),Singular(nn))
	! call SVD_Truncate(matrixtmp,nn,nn,nn,UU,VV,Singular,option%tol_comp,rank)
	! write(*,*)Singular(1),schulz_op%A2norm,'nimade'
	! schulz_op%A2norm=Singular(1)
	! deallocate(UU,VV,Singular)
	! deallocate(matrixtmp)
	! deallocate(matrixtmp1)


	stats%Flop_factor = stats%Flop_tmp

end subroutine BF_compute_schulz_init


recursive subroutine BF_inverse_partitionedinverse_IplusButter(blocks_io,level_butterfly_target,recurlevel,option,error_inout,stats,ptree,msh,pgno)

    use BPACK_DEFS
	use MISC_Utilities


    use omp_lib

    implicit none

	integer level_c,rowblock
    integer blocks1, blocks2, blocks3, level_butterfly, i, j, k, num_blocks
    integer num_col, num_row, recurlevel, mm, nn, ii, jj,tt,kk1,kk2,rank,err_cnt
    character chara
    real(kind=8) T0,err_avr
    type(matrixblock),pointer::blocks_A,blocks_B,blocks_C,blocks_D
    type(matrixblock)::blocks_io
    type(matrixblock)::blocks_schur
    integer rank_new_max,rank0
	real(kind=8):: rank_new_avr,error,rate
	integer niter
	real(kind=8):: error_inout
	integer itermax,ntry
	real(kind=8):: n1,n2,Memory
	DT, allocatable::matrix_small(:,:)
	type(Hoption)::option
	type(Hstat)::stats
	integer level_butterfly_target,pgno,pgno1
	type(proctree)::ptree
	type(mesh)::msh
	integer ierr
	type(matrixblock)::partitioned_block

	error_inout=0

	if(blocks_io%level_butterfly==0)then
		call LR_SMW(blocks_io,Memory,ptree,stats,pgno)
		return
    else
		allocate(partitioned_block%sons(2,2))

		blocks_A => partitioned_block%sons(1,1)
		blocks_B => partitioned_block%sons(1,2)
		blocks_C => partitioned_block%sons(2,1)
		blocks_D => partitioned_block%sons(2,2)

		! split into four smaller butterflies
		n1 = OMP_get_wtime()
		call BF_split(blocks_io, partitioned_block,ptree,stats,msh)
		n2 = OMP_get_wtime()
		stats%Time_split = stats%Time_split + n2-n1


		if(IOwnPgrp(ptree,blocks_D%pgno))then

			! partitioned inverse of D
			! level_butterfly=level_butterfly_target-1
			level_butterfly=blocks_D%level_butterfly
			pgno1 = blocks_D%pgno
			call BF_inverse_partitionedinverse_IplusButter(blocks_D,level_butterfly,recurlevel+1,option,error,stats,ptree,msh,pgno1)
			error_inout = max(error_inout, error)

			! construct the schur complement A-BD^-1C

			! level_butterfly = level_butterfly_target-1
			level_butterfly = blocks_A%level_butterfly

			! write(*,*)'A-BDC',level_butterfly,level


			call BF_get_rank_ABCD(partitioned_block,rank0)
			rate=1.2d0
			call BF_randomized(blocks_A%pgno,level_butterfly,rank0,rate,blocks_A,partitioned_block,BF_block_MVP_inverse_A_minusBDinvC_dat,error,'A-BD^-1C',option,stats,ptree,msh)
			stats%Flop_Factor=stats%Flop_Factor+stats%Flop_Tmp
			error_inout = max(error_inout, error)

			! write(*,*)'ddd1'
			! partitioned inverse of the schur complement
			! level_butterfly=level_butterfly_target-1
			level_butterfly=blocks_A%level_butterfly
			pgno1 = blocks_D%pgno
			call BF_inverse_partitionedinverse_IplusButter(blocks_A,level_butterfly,recurlevel+1,option,error,stats,ptree,msh,pgno1)
			error_inout = max(error_inout, error)
			call BF_get_rank_ABCD(partitioned_block,rank0)
		else
			rank0=0
		endif
		call MPI_ALLREDUCE(MPI_IN_PLACE, rank0, 1,MPI_integer, MPI_MAX, ptree%pgrp(blocks_io%pgno)%Comm,ierr)
		call MPI_ALLREDUCE(MPI_IN_PLACE, error_inout, 1,MPI_double_precision, MPI_MAX, ptree%pgrp(blocks_io%pgno)%Comm,ierr)


		level_butterfly = level_butterfly_target
		rate=1.2d0
		call BF_randomized(blocks_io%pgno,level_butterfly,rank0,rate,blocks_io,partitioned_block,BF_block_MVP_inverse_ABCD_dat,error,'ABCDinverse',option,stats,ptree,msh)
		stats%Flop_Factor=stats%Flop_Factor+stats%Flop_Tmp
		error_inout = max(error_inout, error)

		! stop

		if(option%verbosity>=2 .and. recurlevel==0 .and. ptree%MyID==Main_ID)write(*,'(A23,A6,I3,A8,I3,A11,Es14.7)')' RecursiveI ',' rank:',blocks_io%rankmax,' L_butt:',blocks_io%level_butterfly,' error:',error_inout

		do ii=1,2
		do jj=1,2
			call BF_delete(partitioned_block%sons(ii,jj),1)
		enddo
		enddo
		deallocate(partitioned_block%sons)

		return

	end if
end subroutine BF_inverse_partitionedinverse_IplusButter


subroutine BF_split(blocks_i,blocks_o,ptree,stats,msh)
    use BPACK_DEFS
	use MISC_Utilities


    use omp_lib

    implicit none
	integer level_p,ADflag,iii,jjj
	integer mm1,mm2,nn1,nn2,M1,M2,N1,N2,ii,jj,kk,j,i,mm,nn
	integer level_butterfly, num_blocks, level_butterfly_c, num_blocks_c,level,num_col,num_row,num_rowson,num_colson

    type(matrixblock),target::blocks_i
    type(matrixblock)::blocks_o,blocks_dummy
    type(matrixblock),pointer::blocks_A,blocks_B,blocks_C,blocks_D,blocks
	DT,allocatable:: matrixtemp1(:,:),matrixtemp2(:,:),vin(:,:),vout1(:,:),vout2(:,:)
	DT::ctemp1,ctemp2
	type(mesh)::msh
	type(proctree)::ptree
	type(Hstat)::stats
	integer pgno


	blocks_A=>blocks_o%sons(1,1)
	blocks_B=>blocks_o%sons(1,2)
	blocks_C=>blocks_o%sons(2,1)
	blocks_D=>blocks_o%sons(2,2)

	if(blocks_i%level_butterfly==0)then
		level_butterfly=GetTreelevel(msh%Maxgroup)-1-blocks_i%level-1
	else
		level_butterfly=max(blocks_i%level_butterfly-2,0)
	endif


	!*** try to use the same process group as blocks_i
	pgno = blocks_i%pgno
	do while(level_butterfly<ptree%nlevel-GetTreelevel(pgno))
		pgno = pgno*2
	enddo


	do iii=1,2
	do jjj=1,2
		blocks=>blocks_o%sons(iii,jjj)
		blocks%level = blocks_i%level+1
		blocks%row_group = blocks_i%row_group*2+iii-1
		blocks%col_group = blocks_i%col_group*2+jjj-1
		blocks%style = blocks_i%style
		blocks%headm = msh%basis_group(blocks%row_group)%head
		blocks%M = msh%basis_group(blocks%row_group)%tail-msh%basis_group(blocks%row_group)%head+1
		blocks%headn = msh%basis_group(blocks%col_group)%head
		blocks%N = msh%basis_group(blocks%col_group)%tail-msh%basis_group(blocks%col_group)%head+1
		blocks%pgno = pgno
		call ComputeParallelIndices(blocks,pgno,ptree,msh,0)
	enddo
	enddo

	if(blocks_i%level_butterfly==0)then

		kk = size(blocks_i%ButterflyU%blocks(1)%matrix,2)
		do iii=1,2
		do jjj=1,2
			blocks=>blocks_o%sons(iii,jjj)
			blocks%level_butterfly=0
			blocks%level_half = 0
			allocate(blocks%ButterflyU%blocks(1))
			allocate(blocks%ButterflyV%blocks(1))
			if(IOwnPgrp(ptree,blocks%pgno))then
				allocate(blocks%ButterflyU%blocks(1)%matrix(blocks%M_loc,kk))
				allocate(blocks%ButterflyV%blocks(1)%matrix(blocks%N_loc,kk))
				blocks%rankmax = kk
				blocks%rankmin = kk
				blocks%ButterflyU%nblk_loc=1
				blocks%ButterflyU%inc=1
				blocks%ButterflyU%idx=1
				blocks%ButterflyV%nblk_loc=1
				blocks%ButterflyV%inc=1
				blocks%ButterflyV%idx=1
			endif
			call Redistribute1Dto1D(blocks_i%ButterflyU%blocks(1)%matrix,blocks_i%M_p,blocks_i%headm,blocks_i%pgno,blocks%ButterflyU%blocks(1)%matrix,blocks%M_p,blocks%headm,blocks%pgno,kk,ptree)
			call Redistribute1Dto1D(blocks_i%ButterflyV%blocks(1)%matrix,blocks_i%N_p,blocks_i%headn,blocks_i%pgno,blocks%ButterflyV%blocks(1)%matrix,blocks%N_p,blocks%headn,blocks%pgno,kk,ptree)
		enddo
		enddo

	else

	   !**** first redistribute blocks_i into blocks_dummy%sons of the same butterfly levels
		blocks_dummy%level_butterfly = blocks_i%level_butterfly
		blocks_dummy%level_half = blocks_i%level_half
		allocate(blocks_dummy%sons(2,2))
		do ii=1,2
		do jj=1,2
			allocate(blocks_dummy%sons(ii,jj)%ButterflyKerl(blocks_dummy%level_butterfly))
			blocks_dummy%sons(ii,jj)%level_butterfly=blocks_dummy%level_butterfly
			blocks_dummy%sons(ii,jj)%level_half=blocks_dummy%level_half
		enddo
		enddo


		do level=0,blocks_dummy%level_butterfly+1
			if(level==0)then
				call BF_all2all_V_split(blocks_i,blocks_i%pgno,level,blocks_dummy,blocks_o%sons(1,1)%pgno,level,stats,ptree)
			elseif(level==blocks_i%level_butterfly+1)then
				call BF_all2all_U_split(blocks_i,blocks_i%pgno,level,blocks_dummy,blocks_o%sons(1,1)%pgno,level,stats,ptree)
			else
				call BF_all2all_ker_split(blocks_i,blocks_i%pgno,level,blocks_dummy,blocks_o%sons(1,1)%pgno,level,stats,ptree)
			endif
		enddo
		!**** next convert blocks_dummy%sons into  blocks_o%sons
		call BF_convert_to_smallBF(blocks_dummy,blocks_o,stats,ptree)
		do ii=1,2
		do jj=1,2
			call BF_delete(blocks_dummy%sons(ii,jj),1)
		enddo
		enddo
		deallocate(blocks_dummy%sons)
	endif

	do ii=1,2
	do jj=1,2
		call BF_get_rank(blocks_o%sons(ii,jj),ptree)
	enddo
	enddo

	! mm1=msh%basis_group(blocks_A%row_group)%tail-msh%basis_group(blocks_A%row_group)%head+1
	! nn1=msh%basis_group(blocks_A%col_group)%tail-msh%basis_group(blocks_A%col_group)%head+1
	! mm2=msh%basis_group(blocks_D%row_group)%tail-msh%basis_group(blocks_D%row_group)%head+1
	! nn2=msh%basis_group(blocks_D%col_group)%tail-msh%basis_group(blocks_D%col_group)%head+1


	! allocate(vin(nn1+nn2,1))
	! vin = 1
	! allocate(vout1(mm1+mm2,1))
	! vout1 = 0
	! allocate(vout2(mm1+mm2,1))
	! vout2 = 0

	! ctemp1 = 1d0; ctemp2 = 0d0
	! call BF_block_MVP_dat(blocks_i,'N',mm1+mm2,nn1+nn2,1,vin,vout1,ctemp1,ctemp2)

	! ctemp1 = 1d0; ctemp2 = 0d0
	! call BF_block_MVP_dat(blocks_A,'N',mm1,nn1,1,vin(1:nn1,:),vout2(1:mm1,:),ctemp1,ctemp2)
	! ctemp1 = 1d0; ctemp2 = 1d0
	! call BF_block_MVP_dat(blocks_B,'N',mm1,nn2,1,vin(1+nn1:nn1+nn2,:),vout2(1:mm1,:),ctemp1,ctemp2)

	! ctemp1 = 1d0; ctemp2 = 0d0
	! call BF_block_MVP_dat(blocks_C,'N',mm2,nn1,1,vin(1:nn1,:),vout2(1+mm1:mm1+mm2,:),ctemp1,ctemp2)
	! ctemp1 = 1d0; ctemp2 = 1d0
	! call BF_block_MVP_dat(blocks_D,'N',mm2,nn2,1,vin(1+nn1:nn1+nn2,:),vout2(1+mm1:mm1+mm2,:),ctemp1,ctemp2)

	! write(*,*)'spliting error:',fnorm(vout1-vout2,mm1+mm2,1)/fnorm(vout1,mm1+mm2,1)
	! deallocate(vin,vout1,vout2)


end subroutine BF_split


subroutine BF_get_rank_ABCD(partitioned_block,rankmax)

    use BPACK_DEFS
    implicit none

	integer rankmax,ii,jj
    type(matrixblock)::partitioned_block

	rankmax = -1000
	do ii=1,2
	do jj=1,2
	rankmax = max(rankmax,partitioned_block%sons(ii,jj)%rankmax)
	enddo
	enddo
end subroutine BF_get_rank_ABCD



!**** Update one off-diagonal block in HODLR compressed as
! Bplus/Butterfly/LR by multiplying on it left the inverse of diagonal block
! If LR, call LR_Sblock; if butterfly, call BF_randomized; if Bplus, call Bplus_randomized_constr
	!ho_bf1: working HODLR
	!level_c: level# of the block in HODLR
	!rowblock: block# of the block at this level in HODLR
	!option: containing compression options
	!stats: statistics
	!ptree: process tree
subroutine Bplus_Sblock_randomized_memfree(ho_bf1,level_c,rowblock,option,stats,ptree,msh)

    use BPACK_DEFS
	use omp_lib
    implicit none

	integer level_c,rowblock
    integer blocks1, blocks2, blocks3, level_butterfly, i, j, k, num_blocks
    integer num_col, num_row, level, mm, nn, ii, jj,tt
    character chara
    real(kind=8) T0
    type(blockplus),pointer::bplus
	type(matrixblock)::block_old
	type(matrixblock),pointer::block_o
    integer::rank_new_max
	real(kind=8)::rank_new_avr,error,rate,rankrate_inner,rankrate_outter
	integer niter,rank,ntry,rank0,rank0_inner,rank0_outter
	real(kind=8):: error_inout
	real(kind=8):: n1,n2
	type(Hoption)::option
	type(Hstat)::stats
	type(hobf)::ho_bf1
	type(proctree)::ptree
	type(mesh)::msh

	error_inout=0

	call Bplus_copy(ho_bf1%levels(level_c)%BP(rowblock),ho_bf1%levels(level_c)%BP_inverse_update(rowblock))
	!!!!!!! the forward block BP can be deleted if not used in solution phase


    bplus =>  ho_bf1%levels(level_c)%BP_inverse_update(rowblock)
	if(bplus%Lplus==1)then

		block_o =>  ho_bf1%levels(level_c)%BP_inverse_update(rowblock)%LL(1)%matrices_block(1)
		level_butterfly=block_o%level_butterfly

		if(level_butterfly==0)then
			call LR_Sblock(ho_bf1,level_c,rowblock,ptree,stats)
		else
			ho_bf1%ind_lv=level_c
			ho_bf1%ind_bk=rowblock
			rank0 = block_o%rankmax
			rate = 1.2d0
			call BF_randomized(block_o%pgno,level_butterfly,rank0,rate,block_o,ho_bf1,BF_block_MVP_Sblock_dat,error_inout,'Sblock',option,stats,ptree,msh,msh)
			stats%Flop_Factor=stats%Flop_Factor+stats%Flop_Tmp
		end if

		if(ptree%MyID==Main_ID .and. option%verbosity>=1)write(*,'(A10,I5,A6,I3,A8,I3,A11,Es14.7)')'OneL No. ',rowblock,' rank:',block_o%rankmax,' L_butt:',block_o%level_butterfly,' error:',error_inout


	else

		ho_bf1%ind_lv=level_c
		ho_bf1%ind_bk=rowblock
		Bplus =>  ho_bf1%levels(level_c)%BP_inverse_update(rowblock)
		block_o =>  ho_bf1%levels(level_c)%BP_inverse_update(rowblock)%LL(1)%matrices_block(1)

		rank0_inner = Bplus%LL(2)%rankmax
		rankrate_inner = 2.0d0

		rank0_outter = block_o%rankmax
		rankrate_outter=1.2d0
		level_butterfly = block_o%level_butterfly
		call Bplus_randomized_constr(level_butterfly,Bplus,ho_bf1,rank0_inner,rankrate_inner,Bplus_block_MVP_Sblock_dat,rank0_outter,rankrate_outter,Bplus_block_MVP_Outter_Sblock_dat,error_inout,'Sblock+',option,stats,ptree,msh)

		block_o =>  ho_bf1%levels(level_c)%BP_inverse_update(rowblock)%LL(1)%matrices_block(1)

		if(option%verbosity>=1 .and. ptree%myid==ptree%pgrp(Bplus%LL(1)%matrices_block(1)%pgno)%head)write(*,'(A10,I5,A6,I3,A8,I3,A11,Es14.7)')'Mult No. ',rowblock,' rank:',block_o%rankmax,' L_butt:',block_o%level_butterfly,' error:',error_inout


	end if

    return

end subroutine Bplus_Sblock_randomized_memfree



subroutine Bplus_inverse_schur_partitionedinverse(ho_bf1,level_c,rowblock,option,stats,ptree,msh)

    use BPACK_DEFS
	use MISC_Utilities


    use omp_lib
    use Bplus_compress

    implicit none

	integer level_c,rowblock,ierr
    integer blocks1, blocks2, blocks3, level_butterfly, i, j, k, num_blocks,level_butterfly_loc
    integer num_col, num_row, level, mm, nn, ii, jj,tt,ll,llplus,bb,mmb
    character chara
    real(kind=8) T0
    type(matrixblock),pointer::block_o,block_off1,block_off2
    type(matrixblock),pointer::blocks_o_D
    type(matrixblock)::block_tmp
	type(blockplus),pointer::Bplus,Bplus_schur
    integer rank_new_max
	real(kind=8):: rank_new_avr,error,err_avr,err_max
	integer niter
	real(kind=8):: error_inout,rate,rankrate_inner,rankrate_outter
	integer itermax,ntry,cnt,cnt_partial
	real(kind=8):: n1,n2,n3,n4,Memory
	integer rank0,rank0_inner,rank0_outter,Lplus,level_BP,levelm,groupm_start,ij_loc,edge_s,edge_e,edge_first,idx_end_m_ref,idx_start_m_ref,idx_start_b,idx_end_b
	DT,allocatable:: matin(:,:),matout(:,:),matin_tmp(:,:),matout_tmp(:,:)
	DT:: ctemp1,ctemp2
	integer, allocatable :: ipiv(:)
	type(Hoption)::option
	type(Hstat)::stats
	type(hobf)::ho_bf1
	type(matrixblock):: agent_block
	type(blockplus):: agent_bplus
	type(proctree) :: ptree
	type(mesh) :: msh


    bplus => ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)

	if(bplus%Lplus==1)then
		call BF_inverse_schur_partitionedinverse(ho_bf1,level_c,rowblock,error_inout,option,stats,ptree,msh)
	else
		ctemp1 = 1d0
		ctemp2 = 0d0

		block_off1 => ho_bf1%levels(level_c)%BP_inverse_update(rowblock*2-1)%LL(1)%matrices_block(1)
		block_off2 => ho_bf1%levels(level_c)%BP_inverse_update(rowblock*2)%LL(1)%matrices_block(1)
		block_o => ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%LL(1)%matrices_block(1)
	! write(*,*)block_o%row_group,block_o%col_group,level_c,rowblock,block_o%level,'diao'
		block_o%level_butterfly = block_off1%level_butterfly

		Memory = 0

		error_inout=0

		ho_bf1%ind_lv=level_c
		ho_bf1%ind_bk=rowblock

		rank0_inner = ho_bf1%levels(level_c)%BP_inverse_update(2*rowblock-1)%LL(2)%rankmax
		rankrate_inner = 2.0d0

		rank0_outter = max(block_off1%rankmax,block_off2%rankmax)
		rankrate_outter=1.2d0

		level_butterfly = block_o%level_butterfly

		call Bplus_randomized_constr(level_butterfly,Bplus,ho_bf1,rank0_inner,rankrate_inner,Bplus_block_MVP_minusBC_dat,rank0_outter,rankrate_outter,Bplus_block_MVP_Outter_minusBC_dat,error,'mBC+',option,stats,ptree,msh)
		error_inout = max(error_inout, error)


		! write(*,*)'good!!!!'
		! stop
		n1 = OMP_get_wtime()
		Bplus => ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)
		Lplus = ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%Lplus
		do llplus =Lplus,1,-1
			do bb=1,Bplus%LL(llplus)%Nbound
				block_o => Bplus%LL(llplus)%matrices_block(bb)
				if(IOwnPgrp(ptree,block_o%pgno))then
					!!!!! partial update butterflies at level llplus from left B1 = D^-1xB
					if(llplus/=Lplus)then
						rank0 = block_o%rankmax
						rate=1.2d0
						level_butterfly = block_o%level_butterfly
						call BF_randomized(block_o%pgno,level_butterfly,rank0,rate,block_o,Bplus,Bplus_block_MVP_diagBinvB_dat,error,'L update',option,stats,ptree,msh,msh)
						stats%Flop_Factor=stats%Flop_Factor+stats%Flop_Tmp
						error_inout = max(error_inout, error)
					endif

					!!!!! invert I+B1 to be I+B2
					level_butterfly=block_o%level_butterfly
					call BF_inverse_partitionedinverse_IplusButter(block_o,level_butterfly,0,option,error,stats,ptree,msh,block_o%pgno)
					error_inout = max(error_inout, error)


					if(llplus/=Lplus)then
						rank0 = block_o%rankmax
						rate=1.2d0
						level_butterfly = block_o%level_butterfly
						call BF_randomized(block_o%pgno,level_butterfly,rank0,rate,block_o,Bplus,Bplus_block_MVP_BdiagBinv_dat,error,'R update',option,stats,ptree,msh,msh)
						stats%Flop_Factor=stats%Flop_Factor+stats%Flop_Tmp
						error_inout = max(error_inout, error)
					endif
				endif
			end do
		end do
		n2 = OMP_get_wtime()
		stats%Time_SMW=stats%Time_SMW + n2-n1


		do ll=1,Bplus%Lplus
		Bplus%LL(ll)%rankmax=0
		do bb=1,Bplus%LL(ll)%Nbound
			Bplus%LL(ll)%rankmax=max(Bplus%LL(ll)%rankmax,Bplus%LL(ll)%matrices_block(bb)%rankmax)
		enddo
		call MPI_ALLREDUCE(MPI_IN_PLACE,Bplus%LL(ll)%rankmax,1,MPI_INTEGER,MPI_MAX,ptree%pgrp(Bplus%LL(1)%matrices_block(1)%pgno)%Comm,ierr)
		end do

		rank_new_max = 0
		do ll=1,Lplus
			rank_new_max = max(rank_new_max,Bplus%LL(ll)%rankmax)
		end do

		if(option%verbosity>=1 .and. ptree%myid==ptree%pgrp(Bplus%LL(1)%matrices_block(1)%pgno)%head)write(*,'(A10,I5,A6,I3,A8,I3,A11,Es14.7)')'Mult No. ',rowblock,' rank:',rank_new_max,' L_butt:',Bplus%LL(1)%matrices_block(1)%level_butterfly,' error:',error_inout

	endif

    return

end subroutine Bplus_inverse_schur_partitionedinverse



end module Bplus_factor
