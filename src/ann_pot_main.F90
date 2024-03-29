!*****************************************************************************************
!IMPORTANT: opt_ann should not be passed, for the moment, it is passed because of cal_ann_tb
subroutine cal_ann_main(parini,atoms,symfunc,ann_arr,opt_ann)
    use mod_tightbinding, only: typ_partb
    use mod_parini, only: typ_parini
    use mod_atoms, only: typ_atoms
    use mod_ann, only: typ_ann_arr
    use mod_symfunc, only: typ_symfunc
    use mod_opt_ann, only: typ_opt_ann
    use mod_cent2, only: typ_cent2
    !use mod_tightbinding, only: typ_partb
    implicit none
    type(typ_parini), intent(in):: parini
    type(typ_atoms), intent(inout):: atoms
    type(typ_ann_arr), intent(inout):: ann_arr
    type(typ_symfunc), intent(inout):: symfunc
    type(typ_opt_ann), intent(inout):: opt_ann
    !local variables
    !real(8):: g, g_tb, dis, E0, E1 
    !real(8), allocatable:: xt(:), gt(:)
    integer:: i, j, iat
    type(typ_partb):: partb
    type(typ_cent2):: cent2
    if(trim(ann_arr%approach)=='atombased') then
        call cal_ann_atombased(parini,atoms,symfunc,ann_arr)
    elseif(trim(ann_arr%approach)=='eem1' .or. trim(ann_arr%approach)=='cent1') then
        call cal_ann_cent1(parini,atoms,symfunc,ann_arr)
    elseif(trim(ann_arr%approach)=='cent2') then
        call cent2%cal_ann_cent2(parini,atoms,symfunc,ann_arr)
    elseif(trim(ann_arr%approach)=='centt') then
        call cal_ann_centt(parini,atoms,symfunc,ann_arr)
    elseif(trim(ann_arr%approach)=='cent3') then
        call cal_ann_cent3(parini,atoms,symfunc,ann_arr)
    elseif(trim(ann_arr%approach)=='tb') then
        call cal_ann_tb(parini,partb,atoms,ann_arr,symfunc,opt_ann)
    else
        write(*,'(2a)') 'ERROR: unknown approach in ANN, ',trim(ann_arr%approach)
        stop
    endif
end subroutine cal_ann_main
!*****************************************************************************************
subroutine prefit_cent_ener_ref(parini,ann_arr,symfunc_train,symfunc_valid,atoms_train,atoms_valid,opt_ann)
    use mod_parini, only: typ_parini
    use mod_ann, only: typ_ann_arr
    use mod_symfunc, only: typ_symfunc_arr
    use mod_opt_ann, only: typ_opt_ann
    use mod_atoms, only: typ_atoms, typ_atoms_arr, atom_copy_old
    use dynamic_memory
    implicit none
    type(typ_parini), intent(in):: parini
    type(typ_ann_arr), intent(inout):: ann_arr
    type(typ_symfunc_arr), intent(inout):: symfunc_train, symfunc_valid
    type(typ_atoms_arr), intent(inout):: atoms_train
    type(typ_atoms_arr), intent(inout):: atoms_valid
    type(typ_opt_ann), intent(inout):: opt_ann
    !local variables
    type(typ_atoms):: atoms
    integer:: iconf, istep, iat, ia, isatur, nsatur
    real(8):: rmse, rmse_old, de0, alpha, tt
    real(8), allocatable:: epotall(:), eref_all(:)
    real(8), allocatable:: anat(:), g(:)
    allocate(anat(100),g(100))
    !return
    ann_arr%event='train'
    call convert_opt_x_ann_arr(opt_ann,ann_arr)
    nsatur=3
    isatur=0
    epotall=f_malloc([1.to.atoms_train%nconf],id='epotall')
    eref_all=f_malloc([1.to.atoms_train%nconf],id='eref_all')
    do iconf=1,atoms_train%nconf
        tt=0.d0
        do iat=1,atoms_train%atoms(iconf)%nat
            tt=tt+ann_arr%ann(atoms_train%atoms(iconf)%itypat(iat))%ener_ref
        enddo
        eref_all(iconf)=tt
    enddo
    alpha=1.d0/real(atoms_train%nconf,8)
    do istep=0,50
        rmse=0.d0
        g=0.d0
        do iconf=1,atoms_train%nconf
            call atom_copy_old(atoms_train%atoms(iconf),atoms,'atoms_train%atoms(iconf)->atoms')
            if(istep==0) then
                call cal_ann_main(parini,atoms,symfunc_train%symfunc(iconf),ann_arr,opt_ann)
                epotall(iconf)=atoms%epot
            else
                tt=0.d0
                do iat=1,atoms%nat
                    tt=tt+ann_arr%ann(atoms%itypat(iat))%ener_ref
                enddo
                atoms%epot=epotall(iconf)-eref_all(iconf)+tt
            endif
            rmse=rmse+((atoms_train%atoms(iconf)%epot-atoms%epot)/atoms%nat)**2
            anat=0.d0
            do iat=1,atoms%nat
                anat(atoms%itypat(iat))=anat(atoms%itypat(iat))+1.d0
            enddo
            do ia=1,ann_arr%nann
                g(ia)=g(ia)+2.d0*anat(ia)*(atoms%epot-atoms_train%atoms(iconf)%epot)/atoms%nat**2
            enddo
        enddo
        rmse=sqrt(rmse/atoms_train%nconf)
        if(istep==0) rmse_old=rmse
        if(istep>0 .and. rmse<rmse_old .and. abs(rmse_old-rmse)<1.d-3) then
            isatur=isatur+1
        else
            isatur=0
        endif
        write(*,'(a,i4,3es19.10,i3)') 'pretrain: ',istep,rmse*1.d3, &
            ann_arr%ann(1)%ener_ref,ann_arr%ann(2)%ener_ref,isatur
        if(rmse*1.d3<2.d1) exit
        if(isatur>nsatur) exit
        do ia=1,ann_arr%nann
            de0=alpha*g(ia)
            de0=sign(min(abs(de0),1.d0),de0)
            ann_arr%ann(ia)%ener_ref=ann_arr%ann(ia)%ener_ref-de0
        enddo
        rmse_old=rmse
    enddo
    call f_free(epotall)
    call f_free(eref_all)
    deallocate(anat,g)
    !stop
end subroutine prefit_cent_ener_ref
!*****************************************************************************************
subroutine prefit_cent(parini,ann_arr,symfunc_train,symfunc_valid,atoms_train,atoms_valid,opt_ann)
    use mod_parini, only: typ_parini
    use mod_ann, only: typ_ann_arr
    use mod_symfunc, only: typ_symfunc_arr
    use mod_opt_ann, only: typ_opt_ann
    use mod_atoms, only: typ_atoms, typ_atoms_arr, atom_copy_old
    use dynamic_memory
    implicit none
    type(typ_parini), intent(in):: parini
    type(typ_ann_arr), intent(inout):: ann_arr
    type(typ_symfunc_arr), intent(inout):: symfunc_train, symfunc_valid
    type(typ_atoms_arr), intent(inout):: atoms_train
    type(typ_atoms_arr), intent(inout):: atoms_valid
    type(typ_opt_ann), intent(inout):: opt_ann
    !local variables
    type(typ_atoms):: atoms
    integer:: iconf, istep, iat, ia, isatur, nsatur
    real(8):: rmse, rmse_old, dchi0, dhardness, alpha1, alpha2, tt
    real(8):: qnet
    real(8), allocatable:: anat1(:), g1(:)
    real(8), allocatable:: anat2(:), g2(:)
    allocate(anat1(100),g1(100))
    allocate(anat2(100),g2(100))
    ann_arr%event='train'
    call convert_opt_x_ann_arr(opt_ann,ann_arr)
    nsatur=3
    isatur=0
    alpha1=0.2d0/real(atoms_train%nconf,8)
    alpha2=0.02d0/real(atoms_train%nconf,8)
    do istep=0,50
        rmse=0.d0
        g1=0.d0
        g2=0.d0
        do iconf=1,atoms_train%nconf
            call atom_copy_old(atoms_train%atoms(iconf),atoms,'atoms_train%atoms(iconf)->atoms')
            call cal_ann_main(parini,atoms,symfunc_train%symfunc(iconf),ann_arr,opt_ann)
            rmse=rmse+((atoms_train%atoms(iconf)%epot-atoms%epot)/atoms%nat)**2
            anat1=0.d0
            anat2=0.d0
            do iat=1,atoms%nat
                if(trim(ann_arr%approach)=='eem1' .or. trim(ann_arr%approach)=='cent1' &
                    .or. trim(ann_arr%approach)=='cent2') then
                    qnet=atoms%qat(iat)
                elseif(trim(ann_arr%approach)=='centt') then
                    qnet=atoms%zat(iat)+atoms%qat(iat)
                else
                    write(*,'(2a)') 'ERROR: unknown approach in ANN, ',trim(ann_arr%approach)
                    stop
                endif
                anat1(atoms%itypat(iat))=anat1(atoms%itypat(iat))+qnet
                anat2(atoms%itypat(iat))=anat2(atoms%itypat(iat))+0.5d0*qnet**2
            enddo
            do ia=1,ann_arr%nann
                g1(ia)=g1(ia)+2.d0*anat1(ia)*(atoms%epot-atoms_train%atoms(iconf)%epot)/atoms%nat**2
                g2(ia)=g2(ia)+2.d0*anat2(ia)*(atoms%epot-atoms_train%atoms(iconf)%epot)/atoms%nat**2
            enddo
        enddo
        rmse=sqrt(rmse/atoms_train%nconf)
        if(istep==0) rmse_old=rmse
        if(istep>0 .and. rmse<rmse_old .and. abs(rmse_old-rmse)<1.d-4) then
            isatur=isatur+1
        else
            isatur=0
        endif
        write(*,'(a,i4,5es19.10,i3)') 'prefit: ',istep,rmse*1.d3, &
            ann_arr%ann(1)%chi0,ann_arr%ann(2)%chi0, &
            ann_arr%ann(1)%hardness,ann_arr%ann(2)%hardness,isatur
        if(rmse*1.d3<1.d0) exit
        if(isatur>nsatur) exit
        do ia=1,ann_arr%nann
            dchi0=alpha1*g1(ia)
            dchi0=sign(min(abs(dchi0),1.d-1),dchi0)
            ann_arr%ann(ia)%chi0=ann_arr%ann(ia)%chi0-dchi0
            dhardness=alpha2*g2(ia)
            dhardness=sign(min(abs(dhardness),1.d-1),dhardness)
            ann_arr%ann(ia)%hardness=ann_arr%ann(ia)%hardness-dhardness
        enddo
        rmse_old=rmse
    enddo
    deallocate(anat1,g1)
    deallocate(anat2,g2)
end subroutine prefit_cent
!*****************************************************************************************
