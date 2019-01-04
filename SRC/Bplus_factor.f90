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
use Bplus_randomized

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

	use misc
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

	type(RandomBlock), pointer :: random
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


	! ! allocate BP_inverse_schur on the second process grid
	! if(.not. associated(ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%LL))then
		! block_off2 => ho_bf1%levels(level_c)%BP(rowblock*2)%LL(1)%matrices_block(1)
		! allocate(ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%LL(LplusMax))
		! ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%Lplus=ho_bf1%levels(level_c)%BP(rowblock*2)%Lplus
		! do ll=1,LplusMax
			! ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%LL(ll)%Nbound=0
		! end do
		! ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%LL(1)%Nbound = 1
		! ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%LL(1)%rankmax = 0
		! allocate(ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%LL(1)%matrices_block(1))
		! ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%LL(1)%matrices_block(1)%level = block_off2%level
		! ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%LL(1)%matrices_block(1)%level_butterfly = block_off2%level_butterfly
		! ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%LL(1)%matrices_block(1)%col_group = block_off2%col_group
		! ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%LL(1)%matrices_block(1)%row_group = block_off2%col_group
		! ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%LL(1)%matrices_block(1)%style = 2
	! endif

	block_o =>  ho_bf1%levels(level_c)%BP_inverse_schur(rowblock)%LL(1)%matrices_block(1)
	call BF_delete(block_o,1)

	block_o%level_butterfly = 0
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

	use misc
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
	type(RandomBlock), pointer :: random
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
	use misc


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
		call BF_randomized(level_butterfly,rank0,rate,block_o,ho_bf1,BF_block_MVP_inverse_minusBC_dat,error,'minusBC',option,stats,ptree,msh)
		error_inout = max(error_inout, error)
	endif

	pgno = block_o%pgno

	n1 = OMP_get_wtime()
	! if(block_o%level==3)then
	if(level_butterfly>=option%schulzlevel)then
		call BF_inverse_schulziteration_IplusButter(block_o,error,option,stats,ptree,msh)
	else
		call BF_inverse_partitionedinverse_IplusButter(block_o,level_butterfly,option,error,stats,ptree,msh,pgno)
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
	use misc


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
	real(kind=8):: n1,n2,Memory,memory_temp
	type(Hoption)::option
	type(Hstat)::stats
	type(proctree)::ptree
	type(mesh)::msh
	type(schulz_operand)::schulz_op
	DT,allocatable::VecIn(:,:),VecOut(:,:),VecBuff(:,:)
	DT::ctemp1,ctemp2
	character(len=10)::iternumber

	error_inout=0
	level_butterfly=block_o%level_butterfly

	Memory = 0

	mm = block_o%M

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
		call BF_randomized(level_butterfly,rank0,rate,block_Xn,schulz_op,BF_block_MVP_schulz_dat,error,'schulz iter'//TRIM(iternumber),option,stats,ptree,msh,ii)

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
		error_inout = fnorm(VecOut-VecIn,mm,num_vect)/fnorm(VecIn,mm,num_vect)



		if(option%verbosity>=1)write(*,'(A22,A6,I3,A8,I2,A8,I3,A7,Es14.7)')' Schultz ',' rank:',block_Xn%rankmax,' Iter:',ii,' L_butt:',block_Xn%level_butterfly,' error:',error_inout


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
		call BF_get_rank(block_Xn)
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
	use misc


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

	mm = schulz_op%matrices_block%M
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
	call ComputeRange(mm,num_vect,RandVectOut,ranktmp,0,option%tol_comp,Flops=flop)
	stats%Flop_tmp = stats%Flop_tmp + flop

	! computation of B = Q^c*A
	RandVectOut=conjg(cmplx(RandVectOut,kind=8))
	call BF_block_MVP_dat(schulz_op%matrices_block,'T',mm,nn,num_vect,RandVectOut,RandVectIn,cone,czero,ptree,stats)
	RandVectIn =RandVectOut+RandVectIn
	RandVectOut=conjg(cmplx(RandVectOut,kind=8))

	! computation of SVD of B and LR of A
	mn=min(nn,ranktmp)
	allocate (UU(nn,mn),VV(mn,ranktmp),Singular(mn))
	call SVD_Truncate(RandVectIn(1:nn,1:ranktmp),nn,ranktmp,mn,UU,VV,Singular,option%tol_comp,rank,flop=flop)
	stats%Flop_tmp = stats%Flop_tmp + flop
	schulz_op%A2norm=Singular(1)

	deallocate(UU,VV,Singular)

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


recursive subroutine BF_inverse_partitionedinverse_IplusButter(blocks_io,level_butterfly_target,option,error_inout,stats,ptree,msh,pgno)

    use BPACK_DEFS
	use misc


    use omp_lib

    implicit none

	integer level_c,rowblock
    integer blocks1, blocks2, blocks3, level_butterfly, i, j, k, num_blocks
    integer num_col, num_row, level, mm, nn, ii, jj,tt,kk1,kk2,rank,err_cnt
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

	type(partitionedblocks)::partitioned_block

	error_inout=0

	! write(*,*)'inverse ABDC',blocks_io%row_group,blocks_io%col_group,blocks_io%level,blocks_io%level_butterfly

	if(blocks_io%level_butterfly==0)then
		call LR_SMW(blocks_io,Memory,ptree,stats,pgno)
		return
    else
		allocate(partitioned_block%blocks_A)
		allocate(partitioned_block%blocks_B)
		allocate(partitioned_block%blocks_C)
		allocate(partitioned_block%blocks_D)

		blocks_A => partitioned_block%blocks_A
		blocks_B => partitioned_block%blocks_B
		blocks_C => partitioned_block%blocks_C
		blocks_D => partitioned_block%blocks_D

		! split into four smaller butterflies
		n1 = OMP_get_wtime()
		call BF_split(blocks_io, blocks_A, blocks_B, blocks_C, blocks_D,ptree,msh)
		n2 = OMP_get_wtime()
		stats%Time_split = stats%Time_split + n2-n1

		! partitioned inverse of D
		! level_butterfly=level_butterfly_target-1
		level_butterfly=blocks_D%level_butterfly
		if(GetTreelevel(pgno)==ptree%nlevel)then
			pgno1=pgno
		else
			pgno1=pgno*2
		endif
		call BF_inverse_partitionedinverse_IplusButter(blocks_D,level_butterfly,option,error,stats,ptree,msh,pgno1)
		error_inout = max(error_inout, error)

		! construct the schur complement A-BD^-1C

		! level_butterfly = level_butterfly_target-1
		level_butterfly = blocks_A%level_butterfly

		! write(*,*)'A-BDC',level_butterfly,level


		call BF_get_rank_ABCD(partitioned_block,rank0)
		rate=1.2d0
		call BF_randomized(level_butterfly,rank0,rate,blocks_A,partitioned_block,BF_block_MVP_inverse_A_minusBDinvC_dat,error,'A-BD^-1C',option,stats,ptree,msh)
		error_inout = max(error_inout, error)

		! write(*,*)'ddd1'
		! partitioned inverse of the schur complement
		! level_butterfly=level_butterfly_target-1
		level_butterfly=blocks_A%level_butterfly
		if(GetTreelevel(pgno)==ptree%nlevel)then
			pgno1=pgno
		else
			pgno1=pgno*2+1
		endif
		call BF_inverse_partitionedinverse_IplusButter(blocks_A,level_butterfly,option,error,stats,ptree,msh,pgno1)
		error_inout = max(error_inout, error)

		level_butterfly = level_butterfly_target
		call BF_get_rank_ABCD(partitioned_block,rank0)
		rate=1.2d0
		call BF_randomized(level_butterfly,rank0,rate,blocks_io,partitioned_block,BF_block_MVP_inverse_ABCD_dat,error,'ABCDinverse',option,stats,ptree,msh)
		error_inout = max(error_inout, error)



		! stop

		if(option%verbosity>=2 .and. level==0)write(*,'(A23,A6,I3,A8,I3,A11,Es14.7)')' SchurI ',' rank:',blocks_io%rankmax,' L_butt:',blocks_io%level_butterfly,' error:',error_inout

		call BF_delete(blocks_A,1)
		call BF_delete(blocks_B,1)
		call BF_delete(blocks_C,1)
		call BF_delete(blocks_D,1)

		return

	end if
end subroutine BF_inverse_partitionedinverse_IplusButter


subroutine BF_split(blocks_i,blocks_A,blocks_B,blocks_C,blocks_D,ptree,msh)
    use BPACK_DEFS
	use misc


    use omp_lib

    implicit none
	integer level_p,ADflag
	integer mm1,mm2,nn1,nn2,M1,M2,N1,N2,ii,jj,kk,j,i,mm,nn
	integer level_butterfly, num_blocks, level_butterfly_c, num_blocks_c,level,num_col,num_row,num_rowson,num_colson

    type(matrixblock),target::blocks_i,blocks_A,blocks_B,blocks_C,blocks_D
    type(matrixblock),pointer::blocks
	DT,allocatable:: matrixtemp1(:,:),matrixtemp2(:,:),vin(:,:),vout1(:,:),vout2(:,:)
	DT::ctemp1,ctemp2
	type(mesh)::msh
	type(proctree)::ptree
	integer Maxgrp

	Maxgrp=2**(ptree%nlevel)-1


	blocks_A%level = blocks_i%level+1
	blocks_A%row_group = blocks_i%row_group*2
	blocks_A%col_group = blocks_i%col_group*2
	blocks_A%style = blocks_i%style

	blocks_B%level = blocks_i%level+1
	blocks_B%row_group = blocks_i%row_group*2
	blocks_B%col_group = blocks_i%col_group*2+1
	blocks_B%style = blocks_i%style

	blocks_C%level = blocks_i%level+1
	blocks_C%row_group = blocks_i%row_group*2+1
	blocks_C%col_group = blocks_i%col_group*2
	blocks_C%style = blocks_i%style

	blocks_D%level = blocks_i%level+1
	blocks_D%row_group = blocks_i%row_group*2+1
	blocks_D%col_group = blocks_i%col_group*2+1
	blocks_D%style = blocks_i%style


	if(blocks_i%level_butterfly==0)then

		blocks_A%level_butterfly = 0
		blocks_B%level_butterfly = 0
		blocks_C%level_butterfly = 0
		blocks_D%level_butterfly = 0

		allocate(blocks_A%ButterflyU%blocks(1))
		allocate(blocks_B%ButterflyU%blocks(1))
		allocate(blocks_C%ButterflyU%blocks(1))
		allocate(blocks_D%ButterflyU%blocks(1))

		allocate(blocks_A%ButterflyV%blocks(1))
		allocate(blocks_B%ButterflyV%blocks(1))
		allocate(blocks_C%ButterflyV%blocks(1))
		allocate(blocks_D%ButterflyV%blocks(1))

		mm1=msh%basis_group(blocks_A%row_group)%tail-msh%basis_group(blocks_A%row_group)%head+1
		nn1=msh%basis_group(blocks_A%col_group)%tail-msh%basis_group(blocks_A%col_group)%head+1
		mm2=msh%basis_group(blocks_D%row_group)%tail-msh%basis_group(blocks_D%row_group)%head+1
		nn2=msh%basis_group(blocks_D%col_group)%tail-msh%basis_group(blocks_D%col_group)%head+1
		kk = size(blocks_i%ButterflyU%blocks(1)%matrix,2)



		allocate(blocks_A%ButterflyU%blocks(1)%matrix(mm1,kk))
		allocate(blocks_A%ButterflyV%blocks(1)%matrix(nn1,kk))
		blocks_A%ButterflyU%blocks(1)%matrix = blocks_i%ButterflyU%blocks(1)%matrix(1:mm1,1:kk)
		blocks_A%ButterflyV%blocks(1)%matrix = blocks_i%ButterflyV%blocks(1)%matrix(1:nn1,1:kk)
		blocks_A%rankmax = kk
		blocks_A%rankmin = kk

		allocate(blocks_B%ButterflyU%blocks(1)%matrix(mm1,kk))
		allocate(blocks_B%ButterflyV%blocks(1)%matrix(nn2,kk))
		blocks_B%ButterflyU%blocks(1)%matrix = blocks_i%ButterflyU%blocks(1)%matrix(1:mm1,1:kk)
		blocks_B%ButterflyV%blocks(1)%matrix = blocks_i%ButterflyV%blocks(1)%matrix(1+nn1:nn1+nn2,1:kk)
		blocks_B%rankmax = kk
		blocks_B%rankmin = kk

		allocate(blocks_C%ButterflyU%blocks(1)%matrix(mm2,kk))
		allocate(blocks_C%ButterflyV%blocks(1)%matrix(nn1,kk))
		blocks_C%ButterflyU%blocks(1)%matrix = blocks_i%ButterflyU%blocks(1)%matrix(1+mm1:mm1+mm2,1:kk)
		blocks_C%ButterflyV%blocks(1)%matrix = blocks_i%ButterflyV%blocks(1)%matrix(1:nn1,1:kk)
		blocks_C%rankmax = kk
		blocks_C%rankmin = kk

		allocate(blocks_D%ButterflyU%blocks(1)%matrix(mm2,kk))
		allocate(blocks_D%ButterflyV%blocks(1)%matrix(nn2,kk))
		blocks_D%ButterflyU%blocks(1)%matrix = blocks_i%ButterflyU%blocks(1)%matrix(1+mm1:mm1+mm2,1:kk)
		blocks_D%ButterflyV%blocks(1)%matrix = blocks_i%ButterflyV%blocks(1)%matrix(1+nn1:nn1+nn2,1:kk)
		blocks_D%rankmax = kk
		blocks_D%rankmin = kk





		blocks_A%headm=blocks_i%headm
		blocks_A%M=mm1
		blocks_A%headn=blocks_i%headn
		blocks_A%N=nn1
		blocks_B%headm=blocks_i%headm
		blocks_B%M=mm1
		blocks_B%headn=blocks_i%headn+nn1
		blocks_B%N=nn2
		blocks_C%headm=blocks_i%headm+mm1
		blocks_C%M=mm2
		blocks_C%headn=blocks_i%headn
		blocks_C%N=nn1
		blocks_D%headm=blocks_i%headm+mm1
		blocks_D%M=mm2
		blocks_D%headn=blocks_i%headn+nn1
		blocks_D%N=nn2


	else if(blocks_i%level_butterfly==1)then
		blocks_A%level_butterfly = 0
		blocks_B%level_butterfly = 0
		blocks_C%level_butterfly = 0
		blocks_D%level_butterfly = 0

		allocate(blocks_A%ButterflyU%blocks(1))
		allocate(blocks_B%ButterflyU%blocks(1))
		allocate(blocks_C%ButterflyU%blocks(1))
		allocate(blocks_D%ButterflyU%blocks(1))

		allocate(blocks_A%ButterflyV%blocks(1))
		allocate(blocks_B%ButterflyV%blocks(1))
		allocate(blocks_C%ButterflyV%blocks(1))
		allocate(blocks_D%ButterflyV%blocks(1))

		mm1 = size(blocks_i%ButterflyKerl(1)%blocks(1,1)%matrix,1)
		nn1 = size(blocks_i%ButterflyKerl(1)%blocks(1,1)%matrix,2)
		mm2 = size(blocks_i%ButterflyKerl(1)%blocks(2,2)%matrix,1)
		nn2 = size(blocks_i%ButterflyKerl(1)%blocks(2,2)%matrix,2)

		M1 = size(blocks_i%ButterflyU%blocks(1)%matrix,1)
		M2 = size(blocks_i%ButterflyU%blocks(2)%matrix,1)
		N1 = size(blocks_i%ButterflyV%blocks(1)%matrix,1)
		N2 = size(blocks_i%ButterflyV%blocks(2)%matrix,1)

		allocate(blocks_A%ButterflyU%blocks(1)%matrix(M1,nn1))
		allocate(blocks_A%ButterflyV%blocks(1)%matrix(N1,nn1))
		! call gemm_omp(blocks_i%ButterflyU%blocks(1)%matrix,blocks_i%ButterflyKerl(1)%blocks(1,1)%matrix,blocks_A%ButterflyU%blocks(1)%matrix, M1, nn1, mm1)
		call gemmf90(blocks_i%ButterflyU%blocks(1)%matrix,M1,blocks_i%ButterflyKerl(1)%blocks(1,1)%matrix,mm1,blocks_A%ButterflyU%blocks(1)%matrix,M1,'N','N',M1, nn1, mm1,cone,czero)
		blocks_A%ButterflyV%blocks(1)%matrix = blocks_i%ButterflyV%blocks(1)%matrix
		blocks_A%rankmax = nn1
		blocks_A%rankmin = nn1


		allocate(blocks_B%ButterflyU%blocks(1)%matrix(M1,nn2))
		allocate(blocks_B%ButterflyV%blocks(1)%matrix(N2,nn2))
		! call gemm_omp(blocks_i%ButterflyU%blocks(1)%matrix,blocks_i%ButterflyKerl(1)%blocks(1,2)%matrix,blocks_B%ButterflyU%blocks(1)%matrix, M1, nn2, mm1)
		call gemmf90(blocks_i%ButterflyU%blocks(1)%matrix,M1,blocks_i%ButterflyKerl(1)%blocks(1,2)%matrix,mm1,blocks_B%ButterflyU%blocks(1)%matrix,M1,'N','N',M1, nn2, mm1,cone,czero)
		blocks_B%ButterflyV%blocks(1)%matrix = blocks_i%ButterflyV%blocks(2)%matrix
		blocks_B%rankmax = nn2
		blocks_B%rankmin = nn2


		allocate(blocks_C%ButterflyU%blocks(1)%matrix(M2,nn1))
		allocate(blocks_C%ButterflyV%blocks(1)%matrix(N1,nn1))
		! call gemm_omp(blocks_i%ButterflyU%blocks(2)%matrix,blocks_i%ButterflyKerl(1)%blocks(2,1)%matrix,blocks_C%ButterflyU%blocks(1)%matrix, M2, nn1, mm2)
		call gemmf90(blocks_i%ButterflyU%blocks(2)%matrix,M2,blocks_i%ButterflyKerl(1)%blocks(2,1)%matrix,mm2,blocks_C%ButterflyU%blocks(1)%matrix,M2,'N','N',M2, nn1, mm2,cone,czero)
		blocks_C%ButterflyV%blocks(1)%matrix = blocks_i%ButterflyV%blocks(1)%matrix
		blocks_C%rankmax = nn1
		blocks_C%rankmin = nn1

		allocate(blocks_D%ButterflyU%blocks(1)%matrix(M2,nn2))
		allocate(blocks_D%ButterflyV%blocks(1)%matrix(N2,nn2))
		! call gemm_omp(blocks_i%ButterflyU%blocks(2)%matrix,blocks_i%ButterflyKerl(1)%blocks(2,2)%matrix,blocks_D%ButterflyU%blocks(1)%matrix, M2, nn2, mm2)
		call gemmf90(blocks_i%ButterflyU%blocks(2)%matrix,M2,blocks_i%ButterflyKerl(1)%blocks(2,2)%matrix,mm2,blocks_D%ButterflyU%blocks(1)%matrix,M2,'N','N',M2, nn2, mm2,cone,czero)
		blocks_D%ButterflyV%blocks(1)%matrix = blocks_i%ButterflyV%blocks(2)%matrix
		blocks_D%rankmax = nn2
		blocks_D%rankmin = nn2


		blocks_A%headm=blocks_i%headm
		blocks_A%M=M1
		blocks_A%headn=blocks_i%headn
		blocks_A%N=N1
		blocks_B%headm=blocks_i%headm
		blocks_B%M=M1
		blocks_B%headn=blocks_i%headn+N1
		blocks_B%N=N2
		blocks_C%headm=blocks_i%headm+M1
		blocks_C%M=M2
		blocks_C%headn=blocks_i%headn
		blocks_C%N=N1
		blocks_D%headm=blocks_i%headm+M1
		blocks_D%M=M2
		blocks_D%headn=blocks_i%headn+N1
		blocks_D%N=N2


	else
		blocks_A%level_butterfly = blocks_i%level_butterfly-2
		blocks_B%level_butterfly = blocks_i%level_butterfly-2
		blocks_C%level_butterfly = blocks_i%level_butterfly-2
		blocks_D%level_butterfly = blocks_i%level_butterfly-2

		level_butterfly_c = blocks_i%level_butterfly-2
		num_blocks_c = 2**level_butterfly_c

		allocate(blocks_A%ButterflyU%blocks(num_blocks_c))
		allocate(blocks_A%ButterflyV%blocks(num_blocks_c))
		M1=0
		N1=0
		do ii =1,num_blocks_c
			mm1 = size(blocks_i%ButterflyU%blocks(2*ii-1)%matrix,1)
			nn1 = size(blocks_i%ButterflyU%blocks(2*ii-1)%matrix,2)
			mm2 = size(blocks_i%ButterflyU%blocks(2*ii)%matrix,1)
			nn2 = size(blocks_i%ButterflyU%blocks(2*ii)%matrix,2)
			kk = size(blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii-1,1)%matrix,2)
			allocate(blocks_A%ButterflyU%blocks(ii)%matrix(mm1+mm2,kk))
			M1=M1+mm1+mm2
			allocate(matrixtemp1(mm1,kk))
			allocate(matrixtemp2(mm2,kk))
			! call gemm_omp(blocks_i%ButterflyU%blocks(2*ii-1)%matrix,blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii-1,1)%matrix,matrixtemp1,mm1,kk,nn1)

			call gemmf90(blocks_i%ButterflyU%blocks(2*ii-1)%matrix,mm1,blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii-1,1)%matrix,nn1,matrixtemp1,mm1,'N','N',mm1,kk,nn1,cone,czero)

			! call gemm_omp(blocks_i%ButterflyU%blocks(2*ii)%matrix,blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii,1)%matrix,matrixtemp2,mm2,kk,nn2)
			call gemmf90(blocks_i%ButterflyU%blocks(2*ii)%matrix,mm2,blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii,1)%matrix,nn2,matrixtemp2,mm2,'N','N',mm2,kk,nn2,cone,czero)
			blocks_A%ButterflyU%blocks(ii)%matrix(1:mm1,1:kk) = matrixtemp1
			blocks_A%ButterflyU%blocks(ii)%matrix(1+mm1:mm1+mm2,1:kk) = matrixtemp2
			deallocate(matrixtemp1)
			deallocate(matrixtemp2)

			mm1 = size(blocks_i%ButterflyV%blocks(2*ii-1)%matrix,1)
			nn1 = size(blocks_i%ButterflyV%blocks(2*ii-1)%matrix,2)
			mm2 = size(blocks_i%ButterflyV%blocks(2*ii)%matrix,1)
			nn2 = size(blocks_i%ButterflyV%blocks(2*ii)%matrix,2)
			kk = size(blocks_i%ButterflyKerl(1)%blocks(1,2*ii-1)%matrix,1)
			allocate(blocks_A%ButterflyV%blocks(ii)%matrix(mm1+mm2,kk))
			N1=N1+mm1+mm2
			allocate(matrixtemp1(mm1,kk))
			allocate(matrixtemp2(mm2,kk))
			! call gemmNT_omp(blocks_i%ButterflyV%blocks(2*ii-1)%matrix,blocks_i%ButterflyKerl(1)%blocks(1,2*ii-1)%matrix,matrixtemp1, mm1,kk,nn1)
			call gemmf90(blocks_i%ButterflyV%blocks(2*ii-1)%matrix,mm1, blocks_i%ButterflyKerl(1)%blocks(1,2*ii-1)%matrix,kk, matrixtemp1,mm1, 'N','T',mm1,kk,nn1,cone,czero)


			! call gemmNT_omp(blocks_i%ButterflyV%blocks(2*ii)%matrix,blocks_i%ButterflyKerl(1)%blocks(1,2*ii)%matrix,matrixtemp2, mm2,kk,nn2)
			call gemmf90(blocks_i%ButterflyV%blocks(2*ii)%matrix,mm2, blocks_i%ButterflyKerl(1)%blocks(1,2*ii)%matrix,kk, matrixtemp2,mm2, 'N','T',mm2,kk,nn2,cone,czero)
			blocks_A%ButterflyV%blocks(ii)%matrix(1:mm1,1:kk) = matrixtemp1
			blocks_A%ButterflyV%blocks(ii)%matrix(1+mm1:mm1+mm2,1:kk) = matrixtemp2
			deallocate(matrixtemp1)
			deallocate(matrixtemp2)

		end do

		allocate(blocks_B%ButterflyU%blocks(num_blocks_c))
		allocate(blocks_B%ButterflyV%blocks(num_blocks_c))
		do ii =1,num_blocks_c
			mm1 = size(blocks_i%ButterflyU%blocks(2*ii-1)%matrix,1)
			nn1 = size(blocks_i%ButterflyU%blocks(2*ii-1)%matrix,2)
			mm2 = size(blocks_i%ButterflyU%blocks(2*ii)%matrix,1)
			nn2 = size(blocks_i%ButterflyU%blocks(2*ii)%matrix,2)
			kk = size(blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii-1,2)%matrix,2)
			allocate(blocks_B%ButterflyU%blocks(ii)%matrix(mm1+mm2,kk))
			allocate(matrixtemp1(mm1,kk))
			allocate(matrixtemp2(mm2,kk))
			! call gemm_omp(blocks_i%ButterflyU%blocks(2*ii-1)%matrix,blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii-1,2)%matrix,matrixtemp1,mm1,kk,nn1)

			call gemmf90(blocks_i%ButterflyU%blocks(2*ii-1)%matrix,mm1,blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii-1,2)%matrix,nn1,matrixtemp1,mm1,'N','N',mm1,kk,nn1,cone,czero)

			! call gemm_omp(blocks_i%ButterflyU%blocks(2*ii)%matrix,blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii,2)%matrix,matrixtemp2,mm2,kk,nn2)
			call gemmf90(blocks_i%ButterflyU%blocks(2*ii)%matrix,mm2,blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii,2)%matrix,nn2,matrixtemp2,mm2,'N','N',mm2,kk,nn2,cone,czero)
			blocks_B%ButterflyU%blocks(ii)%matrix(1:mm1,1:kk) = matrixtemp1
			blocks_B%ButterflyU%blocks(ii)%matrix(1+mm1:mm1+mm2,1:kk) = matrixtemp2
			deallocate(matrixtemp1)
			deallocate(matrixtemp2)

			mm1 = size(blocks_i%ButterflyV%blocks(2*ii-1+num_blocks_c*2)%matrix,1)
			nn1 = size(blocks_i%ButterflyV%blocks(2*ii-1+num_blocks_c*2)%matrix,2)
			mm2 = size(blocks_i%ButterflyV%blocks(2*ii+num_blocks_c*2)%matrix,1)
			nn2 = size(blocks_i%ButterflyV%blocks(2*ii+num_blocks_c*2)%matrix,2)
			kk = size(blocks_i%ButterflyKerl(1)%blocks(1,2*ii-1+num_blocks_c*2)%matrix,1)
			allocate(blocks_B%ButterflyV%blocks(ii)%matrix(mm1+mm2,kk))
			allocate(matrixtemp1(mm1,kk))
			allocate(matrixtemp2(mm2,kk))
			! call gemmNT_omp(blocks_i%ButterflyV%blocks(2*ii-1+num_blocks_c*2)%matrix,blocks_i%ButterflyKerl(1)%blocks(1,2*ii-1+num_blocks_c*2)%matrix,matrixtemp1, mm1,kk,nn1)
			call gemmf90(blocks_i%ButterflyV%blocks(2*ii-1+num_blocks_c*2)%matrix,mm1, blocks_i%ButterflyKerl(1)%blocks(1,2*ii-1+num_blocks_c*2)%matrix,kk, matrixtemp1,mm1, 'N','T',mm1,kk,nn1,cone,czero)

			! call gemmNT_omp(blocks_i%ButterflyV%blocks(2*ii+num_blocks_c*2)%matrix,blocks_i%ButterflyKerl(1)%blocks(1,2*ii+num_blocks_c*2)%matrix,matrixtemp2, mm2,kk,nn2)
			call gemmf90(blocks_i%ButterflyV%blocks(2*ii+num_blocks_c*2)%matrix,mm2, blocks_i%ButterflyKerl(1)%blocks(1,2*ii+num_blocks_c*2)%matrix,kk, matrixtemp2,mm2, 'N','T',mm2,kk,nn2,cone,czero)
			blocks_B%ButterflyV%blocks(ii)%matrix(1:mm1,1:kk) = matrixtemp1
			blocks_B%ButterflyV%blocks(ii)%matrix(1+mm1:mm1+mm2,1:kk) = matrixtemp2
			deallocate(matrixtemp1)
			deallocate(matrixtemp2)
		end do

		allocate(blocks_C%ButterflyU%blocks(num_blocks_c))
		allocate(blocks_C%ButterflyV%blocks(num_blocks_c))
		do ii =1,num_blocks_c
			mm1 = size(blocks_i%ButterflyU%blocks(2*ii-1+num_blocks_c*2)%matrix,1)
			nn1 = size(blocks_i%ButterflyU%blocks(2*ii-1+num_blocks_c*2)%matrix,2)
			mm2 = size(blocks_i%ButterflyU%blocks(2*ii+num_blocks_c*2)%matrix,1)
			nn2 = size(blocks_i%ButterflyU%blocks(2*ii+num_blocks_c*2)%matrix,2)
			kk = size(blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii-1+num_blocks_c*2,1)%matrix,2)
			allocate(blocks_C%ButterflyU%blocks(ii)%matrix(mm1+mm2,kk))
			allocate(matrixtemp1(mm1,kk))
			allocate(matrixtemp2(mm2,kk))
			! call gemm_omp(blocks_i%ButterflyU%blocks(2*ii-1+num_blocks_c*2)%matrix,blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii-1+num_blocks_c*2,1)%matrix,matrixtemp1,mm1,kk,nn1)
			call gemmf90(blocks_i%ButterflyU%blocks(2*ii-1+num_blocks_c*2)%matrix,mm1,blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii-1+num_blocks_c*2,1)%matrix,nn1,matrixtemp1,mm1,'N','N',mm1,kk,nn1,cone,czero)
			! call gemm_omp(blocks_i%ButterflyU%blocks(2*ii+num_blocks_c*2)%matrix,blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii+num_blocks_c*2,1)%matrix,matrixtemp2,mm2,kk,nn2)
			call gemmf90(blocks_i%ButterflyU%blocks(2*ii+num_blocks_c*2)%matrix,mm2,blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii+num_blocks_c*2,1)%matrix,nn2,matrixtemp2,mm2,'N','N',mm2,kk,nn2,cone,czero)
			blocks_C%ButterflyU%blocks(ii)%matrix(1:mm1,1:kk) = matrixtemp1
			blocks_C%ButterflyU%blocks(ii)%matrix(1+mm1:mm1+mm2,1:kk) = matrixtemp2
			deallocate(matrixtemp1)
			deallocate(matrixtemp2)

			mm1 = size(blocks_i%ButterflyV%blocks(2*ii-1)%matrix,1)
			nn1 = size(blocks_i%ButterflyV%blocks(2*ii-1)%matrix,2)
			mm2 = size(blocks_i%ButterflyV%blocks(2*ii)%matrix,1)
			nn2 = size(blocks_i%ButterflyV%blocks(2*ii)%matrix,2)
			kk = size(blocks_i%ButterflyKerl(1)%blocks(2,2*ii-1)%matrix,1)
			allocate(matrixtemp1(mm1,kk))
			allocate(matrixtemp2(mm2,kk))
			allocate(blocks_C%ButterflyV%blocks(ii)%matrix(mm1+mm2,kk))
			! call gemmNT_omp(blocks_i%ButterflyV%blocks(2*ii-1)%matrix,blocks_i%ButterflyKerl(1)%blocks(2,2*ii-1)%matrix,matrixtemp1, mm1,kk,nn1)
			call gemmf90(blocks_i%ButterflyV%blocks(2*ii-1)%matrix,mm1, blocks_i%ButterflyKerl(1)%blocks(2,2*ii-1)%matrix,kk, matrixtemp1,mm1, 'N','T',mm1,kk,nn1,cone,czero)


			! call gemmNT_omp(blocks_i%ButterflyV%blocks(2*ii)%matrix,blocks_i%ButterflyKerl(1)%blocks(2,2*ii)%matrix,matrixtemp2, mm2,kk,nn2)
			call gemmf90(blocks_i%ButterflyV%blocks(2*ii)%matrix,mm2, blocks_i%ButterflyKerl(1)%blocks(2,2*ii)%matrix,kk, matrixtemp2,mm2, 'N','T',mm2,kk,nn2,cone,czero)
			blocks_C%ButterflyV%blocks(ii)%matrix(1:mm1,1:kk) = matrixtemp1
			blocks_C%ButterflyV%blocks(ii)%matrix(1+mm1:mm1+mm2,1:kk) = matrixtemp2
			deallocate(matrixtemp1)
			deallocate(matrixtemp2)
		end do

		allocate(blocks_D%ButterflyU%blocks(num_blocks_c))
		allocate(blocks_D%ButterflyV%blocks(num_blocks_c))
		M2=0
		N2=0
		do ii =1,num_blocks_c
			mm1 = size(blocks_i%ButterflyU%blocks(2*ii-1+num_blocks_c*2)%matrix,1)
			nn1 = size(blocks_i%ButterflyU%blocks(2*ii-1+num_blocks_c*2)%matrix,2)
			mm2 = size(blocks_i%ButterflyU%blocks(2*ii+num_blocks_c*2)%matrix,1)
			nn2 = size(blocks_i%ButterflyU%blocks(2*ii+num_blocks_c*2)%matrix,2)
			kk = size(blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii-1+num_blocks_c*2,2)%matrix,2)
			allocate(blocks_D%ButterflyU%blocks(ii)%matrix(mm1+mm2,kk))
			M2=M2+mm1+mm2
			allocate(matrixtemp1(mm1,kk))
			allocate(matrixtemp2(mm2,kk))
			! call gemm_omp(blocks_i%ButterflyU%blocks(2*ii-1+num_blocks_c*2)%matrix,blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii-1+num_blocks_c*2,2)%matrix,matrixtemp1,mm1,kk,nn1)

			call gemmf90(blocks_i%ButterflyU%blocks(2*ii-1+num_blocks_c*2)%matrix,mm1,blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii-1+num_blocks_c*2,2)%matrix,nn1,matrixtemp1,mm1,'N','N',mm1,kk,nn1,cone,czero)

			! call gemm_omp(blocks_i%ButterflyU%blocks(2*ii+num_blocks_c*2)%matrix,blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii+num_blocks_c*2,2)%matrix,matrixtemp2,mm2,kk,nn2)
			call gemmf90(blocks_i%ButterflyU%blocks(2*ii+num_blocks_c*2)%matrix,mm2,blocks_i%ButterflyKerl(level_butterfly_c+2)%blocks(2*ii+num_blocks_c*2,2)%matrix,nn2,matrixtemp2,mm2,'N','N',mm2,kk,nn2,cone,czero)
			blocks_D%ButterflyU%blocks(ii)%matrix(1:mm1,1:kk) = matrixtemp1
			blocks_D%ButterflyU%blocks(ii)%matrix(1+mm1:mm1+mm2,1:kk) = matrixtemp2
			deallocate(matrixtemp1)
			deallocate(matrixtemp2)

			mm1 = size(blocks_i%ButterflyV%blocks(2*ii-1+num_blocks_c*2)%matrix,1)
			nn1 = size(blocks_i%ButterflyV%blocks(2*ii-1+num_blocks_c*2)%matrix,2)
			mm2 = size(blocks_i%ButterflyV%blocks(2*ii+num_blocks_c*2)%matrix,1)
			nn2 = size(blocks_i%ButterflyV%blocks(2*ii+num_blocks_c*2)%matrix,2)
			kk = size(blocks_i%ButterflyKerl(1)%blocks(2,2*ii-1+num_blocks_c*2)%matrix,1)
			allocate(blocks_D%ButterflyV%blocks(ii)%matrix(mm1+mm2,kk))
			N2=N2+mm1+mm2
			allocate(matrixtemp1(mm1,kk))
			allocate(matrixtemp2(mm2,kk))
			! call gemmNT_omp(blocks_i%ButterflyV%blocks(2*ii-1+num_blocks_c*2)%matrix,blocks_i%ButterflyKerl(1)%blocks(2,2*ii-1+num_blocks_c*2)%matrix,matrixtemp1, mm1,kk,nn1)
			call gemmf90(blocks_i%ButterflyV%blocks(2*ii-1+num_blocks_c*2)%matrix,mm1, blocks_i%ButterflyKerl(1)%blocks(2,2*ii-1+num_blocks_c*2)%matrix,kk, matrixtemp1,mm1, 'N','T',mm1,kk,nn1,cone,czero)
			! call gemmNT_omp(blocks_i%ButterflyV%blocks(2*ii+num_blocks_c*2)%matrix,blocks_i%ButterflyKerl(1)%blocks(2,2*ii+num_blocks_c*2)%matrix,matrixtemp2, mm2,kk,nn2)
			call gemmf90(blocks_i%ButterflyV%blocks(2*ii+num_blocks_c*2)%matrix,mm2, blocks_i%ButterflyKerl(1)%blocks(2,2*ii+num_blocks_c*2)%matrix,kk, matrixtemp2,mm2, 'N','T',mm2,kk,nn2,cone,czero)
			blocks_D%ButterflyV%blocks(ii)%matrix(1:mm1,1:kk) = matrixtemp1
			blocks_D%ButterflyV%blocks(ii)%matrix(1+mm1:mm1+mm2,1:kk) = matrixtemp2
			deallocate(matrixtemp1)
			deallocate(matrixtemp2)
		end do

		blocks_A%headm=blocks_i%headm
		blocks_A%M=M1
		blocks_A%headn=blocks_i%headn
		blocks_A%N=N1
		blocks_B%headm=blocks_i%headm
		blocks_B%M=M1
		blocks_B%headn=blocks_i%headn+N1
		blocks_B%N=N2
		blocks_C%headm=blocks_i%headm+M1
		blocks_C%M=M2
		blocks_C%headn=blocks_i%headn
		blocks_C%N=N1
		blocks_D%headm=blocks_i%headm+M1
		blocks_D%M=M2
		blocks_D%headn=blocks_i%headn+N1
		blocks_D%N=N2

		if(level_butterfly_c/=0)then
			allocate(blocks_A%ButterflyKerl(level_butterfly_c))
			allocate(blocks_B%ButterflyKerl(level_butterfly_c))
			allocate(blocks_C%ButterflyKerl(level_butterfly_c))
			allocate(blocks_D%ButterflyKerl(level_butterfly_c))
		end if
		do level=1, level_butterfly_c
             num_col=blocks_i%ButterflyKerl(level+1)%num_col
             num_row=blocks_i%ButterflyKerl(level+1)%num_row
             num_colson=num_col/2
             num_rowson=num_row/2
			 blocks_A%ButterflyKerl(level)%num_row=num_rowson
			 blocks_A%ButterflyKerl(level)%num_col=num_colson
			 allocate (blocks_A%ButterflyKerl(level)%blocks(num_rowson,num_colson))
			 blocks_B%ButterflyKerl(level)%num_row=num_rowson
			 blocks_B%ButterflyKerl(level)%num_col=num_colson
			 allocate (blocks_B%ButterflyKerl(level)%blocks(num_rowson,num_colson))
			 blocks_C%ButterflyKerl(level)%num_row=num_rowson
			 blocks_C%ButterflyKerl(level)%num_col=num_colson
			 allocate (blocks_C%ButterflyKerl(level)%blocks(num_rowson,num_colson))
			 blocks_D%ButterflyKerl(level)%num_row=num_rowson
			 blocks_D%ButterflyKerl(level)%num_col=num_colson
			 allocate (blocks_D%ButterflyKerl(level)%blocks(num_rowson,num_colson))

			do j=1, num_col
				 do i=1, num_row
					 mm=size(blocks_i%ButterflyKerl(level+1)%blocks(i,j)%matrix,1)
					 nn=size(blocks_i%ButterflyKerl(level+1)%blocks(i,j)%matrix,2)
					 if (i<=num_rowson .and. j<=num_colson) then
						 allocate (blocks_A%ButterflyKerl(level)%blocks(i,j)%matrix(mm,nn))
						 !$omp parallel do default(shared) private(ii,jj)
						 do jj=1, nn
							 do ii=1, mm
								 blocks_A%ButterflyKerl(level)%blocks(i,j)%matrix(ii,jj)=blocks_i%ButterflyKerl(level+1)%blocks(i,j)%matrix(ii,jj)
							 enddo
						 enddo
						 !$omp end parallel do
					 elseif (i>num_rowson .and. j<=num_colson) then
						 allocate (blocks_C%ButterflyKerl(level)%blocks(i-num_rowson,j)%matrix(mm,nn))
						 !$omp parallel do default(shared) private(ii,jj)
						 do jj=1, nn
							 do ii=1, mm
								 blocks_C%ButterflyKerl(level)%blocks(i-num_rowson,j)%matrix(ii,jj)=blocks_i%ButterflyKerl(level+1)%blocks(i,j)%matrix(ii,jj)
							 enddo
						 enddo
						 !$omp end parallel do
					 elseif (i<=num_rowson .and. j>num_colson) then
						 allocate (blocks_B%ButterflyKerl(level)%blocks(i,j-num_colson)%matrix(mm,nn))
						 !$omp parallel do default(shared) private(ii,jj)
						 do jj=1, nn
							 do ii=1, mm
								 blocks_B%ButterflyKerl(level)%blocks(i,j-num_colson)%matrix(ii,jj)=blocks_i%ButterflyKerl(level+1)%blocks(i,j)%matrix(ii,jj)
							 enddo
						 enddo
						 !$omp end parallel do
					 elseif (i>num_rowson .and. j>num_colson) then
						 allocate (blocks_D%ButterflyKerl(level)%blocks(i-num_rowson,j-num_colson)%matrix(mm,nn))
						 !$omp parallel do default(shared) private(ii,jj)
						 do jj=1, nn
							 do ii=1, mm
								 blocks_D%ButterflyKerl(level)%blocks(i-num_rowson,j-num_colson)%matrix(ii,jj)=blocks_i%ButterflyKerl(level+1)%blocks(i,j)%matrix(ii,jj)
							 enddo
						 enddo
						 !$omp end parallel do
					 endif
				 enddo
			 enddo
		enddo

		call BF_get_rank(blocks_A)
		call BF_get_rank(blocks_B)
		call BF_get_rank(blocks_C)
		call BF_get_rank(blocks_D)

	end if

	! assign M_p,N_p,M_p_db,N_p_db according to the block row layout
	do ii=1,4
		if(ii==1)blocks=>blocks_A
		if(ii==2)blocks=>blocks_B
		if(ii==3)blocks=>blocks_C
		if(ii==4)blocks=>blocks_D
		if(blocks_i%pgno*2>Maxgrp)then
			blocks%pgno=blocks_i%pgno
		else
			if(ii==1 .or. ii==2)blocks%pgno=blocks_i%pgno*2
			if(ii==3 .or. ii==4)blocks%pgno=blocks_i%pgno*2+1
		endif
		call ComputeParallelIndices(blocks,blocks%pgno,ptree,msh,0)
		call ComputeParallelIndices(blocks,blocks%pgno,ptree,msh,1)	! is this needed?
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

	integer rankmax
    type(partitionedblocks)::partitioned_block

	rankmax = -1000
	rankmax = max(rankmax,partitioned_block%blocks_A%rankmax)
	rankmax = max(rankmax,partitioned_block%blocks_B%rankmax)
	rankmax = max(rankmax,partitioned_block%blocks_C%rankmax)
	rankmax = max(rankmax,partitioned_block%blocks_D%rankmax)

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
			call BF_randomized(level_butterfly,rank0,rate,block_o,ho_bf1,BF_block_MVP_Sblock_dat,error_inout,'Sblock',option,stats,ptree,msh,msh)
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

		if(option%verbosity>=1)write(*,'(A10,I5,A6,I3,A8,I3,A11,Es14.7)')'Mult No. ',rowblock,' rank:',block_o%rankmax,' L_butt:',block_o%level_butterfly,' error:',error_inout


	end if

    return

end subroutine Bplus_Sblock_randomized_memfree



subroutine Bplus_inverse_schur_partitionedinverse(ho_bf1,level_c,rowblock,option,stats,ptree,msh)

    use BPACK_DEFS
	use misc


    use omp_lib
    use Bplus_compress

    implicit none

	integer level_c,rowblock
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
	real(kind=8):: n1,n2,Memory
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

				err_max=0


				!!!!! partial update butterflies at level llplus from left B1 = D^-1xB
				if(llplus/=Lplus)then

					n1 = OMP_get_wtime()
					call BF_MoveSingulartoLeft(block_o)
					n2 = OMP_get_wtime()
					! time_tmp = time_tmp + n2 - n1

					level_butterfly = Bplus%LL(llplus)%matrices_block(1)%level_butterfly
					level_BP = Bplus%level
					levelm = ceiling_safe(dble(level_butterfly)/2d0)
					level_butterfly_loc = levelm
					groupm_start=block_o%row_group*2**levelm

					! edge_s =msh%basis_group(block_o%row_group)%head
					! edge_e =msh%basis_group(block_o%row_group)%tail


					! write(*,*)'nidiao',llplus,Lplus,Bplus%LL(llplus+1)%Nbound,Bplus%LL(llplus)%matrices_block(1)%row_group,Bplus%LL(llplus)%matrices_block(1)%col_group

					do ii=1,Bplus%LL(llplus+1)%Nbound
						! edge_first = msh%basis_group(Bplus%LL(llplus+1)%matrices_block(ii)%row_group)%head
						edge_first = Bplus%LL(llplus+1)%matrices_block(ii)%headm

						if(edge_first>=block_o%headm .and. edge_first<=block_o%headm+block_o%M-1)then
							ij_loc = Bplus%LL(llplus+1)%matrices_block(ii)%row_group - groupm_start + 1
							if(level_butterfly_loc==0)then
								write(*,*)'level_butterfly_loc==0 not done'
								stop
							else

								call BF_extract_partial(block_o,level_butterfly_loc,ij_loc,'L',agent_block)
								call Bplus_extract_partial(Bplus,llplus+1,Bplus%LL(llplus+1)%matrices_block(ii)%row_group,agent_bplus,msh)



								rank0 = agent_block%rankmax
								rate=1.2d0
								level_butterfly = agent_block%level_butterfly
								call BF_randomized(level_butterfly,rank0,rate,agent_block,agent_bplus,Bplus_block_MVP_BplusB_dat,error,'L small',option,stats,ptree,msh,agent_block)
								! write(*,*)error,level_butterfly,Bplus%LL(llplus+1)%matrices_block(ii)%level_butterfly,'nimade'
								call BF_copy_partial(agent_block,block_o,level_butterfly_loc,ij_loc,'L',Memory)

								err_max = max(err_max, error)

								call BF_delete(agent_block,1)
								! deallocate(agent_block)
								call Bplus_delete(agent_bplus)
								! deallocate(agent_bplus)

							end if
						end if
					end do


				if(option%verbosity>=2)write(*,'(A30,I7,A6,I3,A11,Es14.7)')' L partial: ll ',llplus,' bb:',bb,' error:',err_max

				end if

				error_inout = max(error_inout, err_max)

				! write(*,*)block_o%level_butterfly,'ahaha'

				!!!!! invert I+B1 to be I+B2
				level_butterfly=block_o%level_butterfly
				call BF_inverse_partitionedinverse_IplusButter(block_o,level_butterfly,option,error,stats,ptree,msh,Bplus%LL(1)%matrices_block(1)%pgno)
				error_inout = max(error_inout, error)


				err_max=0
				!!!!! partial update butterflies at level llplus from right B2xD^-1
				if(llplus/=Lplus)then
					! write(*,*)'hhe'
					n1 = OMP_get_wtime()
					call BF_MoveSingulartoRight(block_o)
					n2 = OMP_get_wtime()
					! time_tmp = time_tmp + n2 - n1
					! write(*,*)'hhe1'
					level_butterfly = Bplus%LL(llplus)%matrices_block(1)%level_butterfly
					level_BP = Bplus%level
					levelm = ceiling_safe(dble(level_butterfly)/2d0)
					level_butterfly_loc = levelm
					groupm_start=block_o%row_group*2**levelm
					! edge_s =msh%basis_group(block_o%row_group)%head
					! edge_e =msh%basis_group(block_o%row_group)%tail


					do ii=1,Bplus%LL(llplus+1)%Nbound
						! edge_first = msh%basis_group(Bplus%LL(llplus+1)%matrices_block(ii)%row_group)%head
						edge_first = Bplus%LL(llplus+1)%matrices_block(ii)%headm
						if(edge_first>=block_o%headm .and. edge_first<=block_o%headm+block_o%M-1)then
							ij_loc = Bplus%LL(llplus+1)%matrices_block(ii)%row_group - groupm_start + 1
							if(level_butterfly_loc==0)then
								write(*,*)'level_butterfly_loc==0 not done'
								stop
							else
	! write(*,*)'hhe2',level_butterfly_loc,ij_loc,block_o%level_butterfly
								cnt_partial = cnt_partial + 1
								! allocate(agent_block(1))

								! allocate(agent_block(1))
								! allocate(agent_bplus)

								call BF_extract_partial(block_o,level_butterfly_loc,ij_loc,'R',agent_block)
								call Bplus_extract_partial(Bplus,llplus+1,Bplus%LL(llplus+1)%matrices_block(ii)%row_group,agent_bplus,msh)




								rank0 = agent_block%rankmax
								rate=1.2d0
								level_butterfly = agent_block%level_butterfly
								call BF_randomized(level_butterfly,rank0,rate,agent_block,agent_bplus,Bplus_block_MVP_BBplus_dat,error,'R small',option,stats,ptree,msh,agent_block)
								call BF_copy_partial(agent_block,block_o,level_butterfly_loc,ij_loc,'R',Memory)

								err_max = max(err_max, error)

								call BF_delete(agent_block,1)
								! deallocate(agent_block)
								call Bplus_delete(agent_bplus)
								! deallocate(agent_bplus)

							end if
						end if
					end do

					! call BF_sym2asym(block_o)

					error_inout = max(error_inout, err_max)

					if(option%verbosity>=2)write(*,'(A30,I7,A6,I3,A11,Es14.7)')' R partial: ll ',llplus,' bb:',bb,' error:',err_max

				end if
			end do
		end do
		n2 = OMP_get_wtime()
		stats%Time_SMW=stats%Time_SMW + n2-n1

		rank_new_max = 0
		do ll=1,Lplus
			rank_new_max = max(rank_new_max,Bplus%LL(ll)%rankmax)
		end do


		if(option%verbosity>=1)write(*,'(A10,I5,A6,I3,A8,I3,A11,Es14.7)')'Mult No. ',rowblock,' rank:',rank_new_max,' L_butt:',Bplus%LL(1)%matrices_block(1)%level_butterfly,' error:',error_inout

	endif

    return

end subroutine Bplus_inverse_schur_partitionedinverse



end module Bplus_factor
