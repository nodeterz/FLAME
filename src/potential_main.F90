!*****************************************************************************************
module mod_potential
    use mod_ann, only: typ_ann_arr
    use mod_electrostatics, only: typ_poisson
    use mod_shortrange, only: typ_tosifumi, typ_shortrange
    implicit none
    private
    integer, parameter:: natmax=1000
    !all potentials
    real(8):: fcalls
    real(8):: fcalls_sec
    character(50):: potcode='unknown'
    character(50):: potential_sec='unknown'
    !selected potentials
    real(8):: cell(3)
    integer:: ntypat
    integer:: natarr(128)
    character(5):: stypat(128)
    real(8):: cellvec(3,3)
    integer:: l_atomic_num(natmax)
    character(20):: perfstatus='unknown'
    character(20):: perfstatus_old='unknown'
    character(5), allocatable :: sat(:)
    !Lenosky TB potential
    integer:: natsi
    !ANN potential
    type(typ_ann_arr):: ann_arr
    character(50):: ann_boundcheck='none'
    character(50):: approach_ann='unknown'
    !MPMD potential
    !BigDFT potential
    logical:: bigdft_restart=.false.
    !VASP potential
    character(256):: comment, comment2
    logical:: vasp5
    logical:: single_point_calculation=.true.
    logical:: vasp_restart=.false.
    logical:: atom_motion(3,natmax)
    !VCBLJ potential
    real(8):: sigmalj(2,2) !sigma(i,j) is the sigma between particle i and particle j
    real(8):: epslj(2,2) !eps(i,j) is the epsilon between particle i and particle j
    real(8):: rcut(2,2) !rcut(i,j) is the cutoff distance between particle i and j
    !real(8):: atmass(2)
    !real(8):: atmassinv(2)
    integer, allocatable:: kinds(:)
    !coulomb potential
    type(typ_poisson):: poisson
    !force potentials
    type(typ_shortrange):: shortrange
    !socket
    INTEGER:: sock_socket, sock_inet, sock_port        ! socket ID & address of the socket
    CHARACTER(LEN=1024) :: sock_host
    INTEGER, PARAMETER  :: MSGLEN=12   ! length of the headers of the driver/wrapper communication protocol
    CHARACTER(LEN=60)   :: sock_extra_string="                                                            "
    real(8)             :: sock_ecutwf(2)
    logical             :: reset=.true.
    public:: natmax, fcalls, fcalls_sec, potcode, potential_sec, cell, ntypat, natarr
    public:: stypat, cellvec, l_atomic_num, perfstatus, perfstatus_old, sat
    public:: natsi, ann_arr, ann_boundcheck, approach_ann, bigdft_restart
    public:: comment, comment2, vasp5, single_point_calculation, vasp_restart
    public:: atom_motion, sigmalj, epslj, rcut, kinds
    public:: poisson, shortrange, sock_socket, sock_inet, sock_port, sock_host
    public:: MSGLEN, sock_extra_string, sock_ecutwf, reset
    public:: init_potential_forces
    public:: fini_potential_forces
    public:: cal_potential_forces
    !type:: typ_potential
    !    contains
    !    procedure, public, pass(self):: init_potential_forces
    !    procedure, public, pass(self):: fini_potential_forces
    !    procedure, public, pass(self):: cal_potential_forces
    !end type typ_potential
contains
!*****************************************************************************************
subroutine init_potential_forces(parini,atoms)
    use mod_parini, only: typ_parini
    use mod_atoms, only: typ_atoms
    implicit none
    type(typ_parini), intent(in):: parini
    type(typ_atoms), intent(inout):: atoms
    !local variables
    fcalls=0.d0
    select case(trim(potcode))
        case('netsock')
            call init_netsock(parini)
        case('lj')
            call init_lennardjones
        case('ltb')
            call init_lenosky_tb(atoms)
        case('mpmd')
            call init_potential_forces_mpmd(atoms)
        case('qsc')
            call init_potential_forces_qsc(atoms)
        case('ann')
            call init_potential_ann(parini,atoms)
        case('bigdft')
            call init_potential_forces_bigdft(atoms)
        case('vasp')
            call init_potential_forces_vasp(atoms)
        !case('coulomb')
        !    call init_potential_forces_coulomb(parini,atoms)
        case('forcefield')
            call init_potential_forces_ff(parini,atoms)
        case('vcblj')
            call init_lennardjones_vc(atoms%nat,atoms%sat)
        case('dftb')
            call init_potential_forces_dftb(atoms)
        case('siesta')
#if defined(HAVE_SIESTA)
            call init_potential_forces_siesta(atoms)
#else
            stop 'ERROR: FLAME is not linked with siesta during compilation.'
#endif
        case default
            stop 'ERROR: potential is unknown'
    end select
end subroutine init_potential_forces
!*****************************************************************************************
subroutine cal_potential_forces(parini,atoms)
    use mod_parini, only: typ_parini
    use mod_atoms, only: typ_atoms, get_rat, update_ratp, set_rat, update_rat
    use mod_processors, only: iproc
    use dynamic_memory
    implicit none
    type(typ_parini), intent(in):: parini
    type(typ_atoms), intent(inout):: atoms
    !local variables
    integer:: iat
    real(8), allocatable:: ratred(:,:), rat_backup(:,:)
    !real(8):: time1, time2
    call f_routine(id='cal_potential_forces')
    allocate(rat_backup(3,atoms%nat))
    call get_rat(atoms,rat_backup)
    call update_ratp(atoms)
    if(trim(atoms%boundcond)=='bulk') then
        allocate(ratred(3,atoms%nat))
        call rxyz_cart2int_alborz(atoms%nat,atoms%cellvec,atoms%ratp,ratred)
        call backtocell_alborz(atoms%nat,atoms%cellvec,ratred)
        call rxyz_int2cart_alborz(atoms%nat,atoms%cellvec,ratred,atoms%ratp)
        call update_rat(atoms,upall=.true.)
        deallocate(ratred)
    elseif(trim(atoms%boundcond)=='slab') then
        allocate(ratred(3,atoms%nat))
        call rxyz_cart2int_alborz(atoms%nat,atoms%cellvec,atoms%ratp,ratred)
        do iat=1,atoms%nat
            ratred(1,iat)=modulo(modulo(ratred(1,iat),1.d0),1.d0)
            ratred(2,iat)=modulo(modulo(ratred(2,iat),1.d0),1.d0)
        enddo
        call rxyz_int2cart_alborz(atoms%nat,atoms%cellvec,ratred,atoms%ratp)
        call update_rat(atoms,upall=.true.)
        deallocate(ratred)
    endif
    do iat=1,atoms%nat
        atoms%fat(1,iat)=0.d0
        atoms%fat(2,iat)=0.d0
        atoms%fat(3,iat)=0.d0
    enddo
    select case(trim(potcode))
        case('netsock')
            call cal_potential_forces_netsock(atoms)
        case('lj')
            call lennardjones(atoms)
        case('ltb')
            call lenosky_tb(parini,atoms)
        case('mpmd')
            call cal_potential_forces_mpmd(atoms)
        case('qsc')
            call cal_potential_forces_qsc(atoms)
        case('ann')
            !call cpu_time(time1)
            call cal_potential_ann(parini,atoms)
            !call cpu_time(time2)
            !write(*,*) 'POT time ',time2-time1
        case('bigdft')
            call cal_potential_forces_bigdft(atoms)
        case('vasp')
            call cal_potential_forces_vasp(atoms)
        !case('coulomb')
        !    call cal_potential_forces_coulomb(atoms)
        case('forcefield')
            call cal_potential_forces_ff(parini,atoms)
        case('vcblj')
            allocate(ratred(3,atoms%nat))
            call rxyz_cart2int_alborz(atoms%nat,atoms%cellvec,atoms%ratp,ratred)
            call lennardjones_vc(iproc,atoms%nat,ratred,atoms%cellvec,atoms%pressure,atoms%fat,atoms%celldv,atoms%stress,atoms%epot,atoms%enth)
            deallocate(ratred)
        case('dftb')
            call cal_potential_forces_dftb(atoms)
        case('siesta')
#if defined(HAVE_SIESTA)
            call cal_potential_forces_siesta(atoms)
#else
            stop 'ERROR: FLAME is not linked with siesta during compilation.'
#endif
        case default
            stop 'ERROR: potential is unknown'
    end select
    fcalls=fcalls+1
    if(parini%drift_potential) then
        call remove_drift(atoms)
    endif
    !do iat=1,atoms%nat
    !    write(27,'(3es17.9)') atoms%fat(1,iat),atoms%fat(2,iat),atoms%fat(3,iat)
    !enddo
    !write(27,'(3es20.12)') sqrt(sum(atoms%fat(1,:)**2)),sqrt(sum(atoms%fat(2,:)**2)),sqrt(sum(atoms%fat(3,:)**2))
    call set_rat(atoms,rat_backup,setall=.true.)
    deallocate(rat_backup)
    call f_release_routine()
end subroutine cal_potential_forces
!*****************************************************************************************
subroutine fini_potential_forces(parini,atoms)
    use mod_parini, only: typ_parini
    use mod_atoms, only: typ_atoms
    implicit none
    type(typ_parini), intent(in):: parini
    type(typ_atoms), intent(in):: atoms
    !local variables
    select case(trim(potcode))
        case('netsock')
            call final_netsock
        case('lj')
            call init_lennardjones
        case('ltb')
        case('mpmd')
        case('qsc')
            call final_potential_forces_qsc
        case('ann')
            call final_potential_ann
        case('bigdft')
            call final_potential_forces_bigdft
        case('vasp')
            call final_potential_forces_vasp
        !case('coulomb')
        !    call final_potential_forces_coulomb
        case('forcefield')
            call final_potential_forces_ff(parini,atoms)
        case('dftb')
            call final_potential_forces_dftb
        case('siesta')
#if defined(HAVE_SIESTA)
            call final_potential_forces_siesta
#else
            stop 'ERROR: FLAME is not linked with siesta during compilation.'
#endif
        case default
            stop 'ERROR: potential is unknown'
    end select
end subroutine fini_potential_forces
!*****************************************************************************************
subroutine remove_drift(atoms)
    use mod_atoms, only: typ_atoms
    implicit none
    type(typ_atoms), intent(inout):: atoms
    real(8):: sum_fx ,sum_fy ,sum_fz
    integer::iat

    sum_fx=0.d0  ;  sum_fy=0.d0   ;   sum_fz=0.d0
    do iat=1,atoms%nat
        sum_fx=sum_fx+atoms%fat(1,iat)
        sum_fy=sum_fy+atoms%fat(2,iat)
        sum_fz=sum_fz+atoms%fat(3,iat)
    enddo
    do iat=1,atoms%nat
        atoms%fat(1,iat)=atoms%fat(1,iat)-(sum_fx/atoms%nat)
        atoms%fat(2,iat)=atoms%fat(2,iat)-(sum_fy/atoms%nat)
        atoms%fat(3,iat)=atoms%fat(3,iat)-(sum_fz/atoms%nat)
    enddo
end subroutine remove_drift
!*****************************************************************************************
end module mod_potential
!*****************************************************************************************
