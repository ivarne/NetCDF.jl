module NetCDF
include("netcdf_c_wrappers.jl")
import Base.show
export show,NcDim,NcVar,NcFile,ncread,ncread!,ncwrite,nccreate,ncsync,ncinfo,ncclose,ncputatt,NC_BYTE,NC_SHORT,NC_INT,NC_FLOAT,NC_DOUBLE, ncgetatt,NC_NOWRITE,NC_WRITE,NC_CLOBBER,NC_NOCLOBBER,NC_CLASSIC_MODEL,NC_64BIT_OFFSET,NC_NETCDF4
#Some constants


jltype2nctype={ Int8=>NC_BYTE,
                Int16=>NC_SHORT,
                Int32=>NC_INT,
                Float32=>NC_FLOAT,
                Float64=>NC_DOUBLE}

nctype2string={ NC_BYTE=>"BYTE",
                NC_SHORT=>"SHORT",
                NC_INT=>"INT",
                NC_FLOAT=>"FLOAT",
                NC_DOUBLE=>"DOUBLE"}


type NcDim
  ncid::Integer
  dimid::Integer
  varid::Integer
  name::String
  dimlen::Integer
  vals::AbstractArray
  atts::Dict{Any,Any}
end

NcDim(name::String,dimlength::Integer;values::Union(AbstractArray,Number)=[],atts::Dict{Any,Any}=Dict{Any,Any}())= 
  begin
    (length(values)>0 && length(values)!=dimlength) ? error("Dimension value vector must have the same length as dimlength!") : nothing
    NcDim(-1,-1,-1,name,dimlength,values,atts)
  end

NcDim(name::String,values::AbstractArray;atts::Dict{Any,Any}=Dict{Any,Any}())= 
  NcDim(name,length(values),values=values,atts=atts)
NcDim(name::String,values::AbstractArray,atts::Dict{Any,Any})= 
  NcDim(name,length(values),values=values,atts=atts)


type NcVar
  ncid::Integer
  varid::Integer
  ndim::Integer
  natts::Integer
  nctype::Integer
  name::String
  dimids::Array{}
  dim::Array{NcDim}
  atts::Dict{Any,Any}
  compress::Integer
end

function NcVar(name::String,dimin::Union(NcDim,Array{NcDim,1});atts::Dict{Any,Any}=Dict{Any,Any}(),t::Union(DataType,Integer)=Float64,compress::Integer=-1)
  dim=[dimin]
  return NcVar(-1,-1,length(dim),length(atts), typeof(t)==DataType ? jltype2nctype[t] : t,name,Array(Int,length(dim)),dim,atts,compress)
end
NcVar(name::String,dimin::Union(NcDim,Array{NcDim,1}),atts::Dict{Any,Any},t::Union(DataType,Integer)=Float64)=NcVar(-1,-1,length(dimin),length(atts), typeof(t)==DataType ? jltype2nctype[t] : t,name,Array(Int,length(dimin)),dimin,atts,-1)

type NcFile
  ncid::Integer
  nvar::Integer
  ndim::Integer
  ngatts::Integer
  vars::Dict{String,NcVar}
  dim::Dict{String,NcDim}
  gatts::Dict{Any,Any}
  nunlimdimid::Integer
  name::String
  omode::Uint16
  in_def_mode::Bool
end
NcFile(ncid::Integer,nvar::Integer,ndim::Integer,ngatts::Integer,vars::Dict{String,NcVar},dim::Dict{String,NcDim},gatts::Dict{Any,Any},nunlimdimid::Integer,name::String,omode::Uint16)=NcFile(ncid,nvar,ndim,ngatts,vars,dim,gatts,nunlimdimid,name,omode,false)

include("netcdf_helpers.jl")

global currentNcFiles=Dict{String,NcFile}()  

# Read block of data from file
function readvar!{T<:Integer}(nc::NcFile, varname::String, retvalsa::Array;start::Array{T,1}=ones(Int,ndims(vals)),count::Array{T,1}=Array(Int,size(vals)))
  ncid=nc.ncid
  haskey(nc.vars,varname) ? nothing : error("NetCDF file $(nc.name) does not have variable $varname")
  if length(start) == 0 start=ones(Int,nc.vars[varname].ndim) end
  if length(count) == 0 count=-ones(Int,nc.vars[varname].ndim) end
  if length(start) != nc.vars[varname].ndim error("Length of start ($(length(start))) must equal the number of variable dimensions ($(nc.vars[varname].ndim))") end
  if length(count) != nc.vars[varname].ndim error("Length of start ($(length(count))) must equal the number of variable dimensions ($(nc.vars[varname].ndim))") end
  
  for i = 1:length(count)
    if count[i] <= 0 count[i] = nc.vars[varname].dim[i].dimlen end
  end
  
  p=prod(count) #Determine size of Array
  
  length(retvalsa) != p && error("Size of output array does not equal number of elements to be read!")
  
  count=Uint[count[i] for i in length(count):-1:1]
  start=Uint[start[i]-1 for i in length(start):-1:1]
  
  varid=nc.vars[varname].varid
  
  nc_get_vara_x!(ncid,varid,start,count,retvalsa)
  
  retvalsa
end
readvar{T<:Integer}(nc::NcFile,varname::String,start::Array{T,1},count::Array{T,1})=readvar(nc,varname,start=start,count=count)

function readvar{T<:Integer}(nc::NcFile, varname::String;start::Array{T,1}=Array(Int,0),count::Array{T,1}=Array(Int,0))
    
    haskey(nc.vars,varname) || error("NetCDF file $(nc.name) does not have variable $varname")
    if length(count) == 0 count=-ones(Int,nc.vars[varname].ndim) end
    for i = 1:length(count)
        if count[i] <= 0 count[i] = nc.vars[varname].dim[i].dimlen end
    end
    p=prod(count) # Determine size of Array
        
    retvalsa = nc.vars[varname].nctype==NC_DOUBLE ? Array(Float64,p) :
               nc.vars[varname].nctype==NC_FLOAT ? Array(Float32,p) :
               nc.vars[varname].nctype==NC_INT ? Array(Int32,p) :
               nc.vars[varname].nctype==NC_SHORT ? Array(Int32,p) :
               nc.vars[varname].nctype==NC_CHAR ? Array(Uint8,p) :
               nc.vars[varname].nctype==NC_BYTE ? Array(Int8,p) :
               nothing
    
    retvalsa == nothing && error("NetCDF type currently not supported, please file an issue on https://github.com/meggart/NetCDF.jl")
    
    readvar!(nc, varname, retvalsa, start=start, count=count)
    
    if length(count)>1 
      return reshape(retvalsa,ntuple(length(count),x->count[x]))
    else
      return retvalsa
    end
end


nc_get_vara_x!(ncid::Integer,varid::Integer,start::Vector{Uint},count::Vector{Uint},retvalsa::Array{Float64})=_nc_get_vara_double_c(ncid,varid,start,count,retvalsa)
nc_get_vara_x!(ncid::Integer,varid::Integer,start::Vector{Uint},count::Vector{Uint},retvalsa::Array{Float32})=_nc_get_vara_float_c(ncid,varid,start,count,retvalsa)
nc_get_vara_x!(ncid::Integer,varid::Integer,start::Vector{Uint},count::Vector{Uint},retvalsa::Array{Int32})=_nc_get_vara_int_c(ncid,varid,start,count,retvalsa)
nc_get_vara_x!(ncid::Integer,varid::Integer,start::Vector{Uint},count::Vector{Uint},retvalsa::Array{Uint8})=_nc_get_vara_text_c(ncid,varid,start,count,retvalsa)
nc_get_vara_x!(ncid::Integer,varid::Integer,start::Vector{Uint},count::Vector{Uint},retvalsa::Array{Int8})=_nc_get_vara_schar_c(ncid,varid,start,count,retvalsa)


function putatt(ncid::Integer,varid::Integer,atts::Dict)
  for a in atts
    name=a[1]
    val=a[2]
    _nc_put_att(ncid,varid,name,val)
  end
end

function putatt(nc::NcFile,varname::String,atts::Dict)
  varid = haskey(nc.vars,varname) ? nc.vars[varname].varid : NC_GLOBAL
  chdef=false
  if (!nc.in_def_mode)
    chdef=true
    _nc_redef_c(nc.ncid)
  end
  putatt(nc.ncid,varid,atts)
  chdef ? _nc_enddef_c(nc.ncid) : nothing
end

function ncputatt(nc::String,varname::String,atts::Dict)
  nc= haskey(currentNcFiles,abspath(nc)) ? currentNcFiles[abspath(nc)] : open(nc,mode=NC_WRITE)
  if (nc.omode==NC_NOWRITE)
    fil=nc.name
    close(nc)
    println("reopening file in WRITE mode")
    open(fil,mode=NC_WRITE)
  end
  putatt(nc,varname,atts)
end


function putvar{T<:Integer}(nc::NcFile,varname::String,vals::Array;start::Array{T,1}=ones(Int,length(size(vals))),count::Array{T,1}=[size(vals)...])
  ncid=nc.ncid
  haskey(nc.vars,varname) ? nothing : error("No variable $varname in file $nc.name")
  nc.vars[varname].ndim==length(start) ? nothing : error("Length of start vector does not equal number of NetCDF variable dimensions")
  nc.vars[varname].ndim==length(count) ? nothing : error("Length of count vector does not equal number of NetCDF variable dimensions")
  start=int(start).-1
  for i=1:length(start)
    count[i] = count[i] < 0 ? nc.vars[varname].dim[i].dimlen - start[i] : count[i]
    start[i]+count[i] > nc.vars[varname].dim[i].dimlen ? error("In dimension $(nc.vars[varname].dim[i].name) start+count exceeds dimension bounds: $(start[i])+$(count[i]) > $(nc.vars[varname].dim[i].dimlen)") : nothing
  end 
  count=uint(count[length(count):-1:1])
  start=uint(start[length(start):-1:1])
  x=vals
  varid=nc.vars[varname].varid
  if nc.vars[varname].nctype==NC_DOUBLE
    _nc_put_vara_double_c(ncid,varid,start,count,float64(x))
  elseif nc.vars[varname].nctype==NC_FLOAT
    _nc_put_vara_float_c(ncid,varid,start,count,float32(x))
  elseif nc.vars[varname].nctype==NC_INT
    _nc_put_vara_int_c(ncid,varid,start,count,int32(x))
  elseif nc.vars[varname].nctype==NC_SHORT
    _nc_put_vara_short_c(ncid,varid,start,count,int16(x))
  elseif nc.vars[varname].nctype==NC_CHAR
    _nc_put_vara_text_c(ncid,varid,start,count,ascii(x))
  elseif nc.vars[varname].nctype==NC_BYTE
    _nc_put_vara_schar_c(ncid,varid,start,count,int8(x))
  end
  NC_VERBOSE ? println("Successfully wrote to file ",ncid) : nothing
end


# Function to synchronize all files with disk
function ncsync()
  for ncf in currentNcFiles
    id=ncf[2].ncid
    _nc_sync_c(int32(id))
  end
end

function sync(nc::NcFile)
  id=nc.ncid
  _nc_sync_c(int32(id))
end

#Function to close netcdf files
function ncclose(fil::String)
  if (haskey(currentNcFiles,abspath(fil)))
    close(currentNcFiles[abspath(fil)])
  else
    println("File $fil not currently opened.")
  end
end
function ncclose()
  for f in keys(currentNcFiles)
    ncclose(f)
  end
end

function create(name::String,varlist::Union(Array{NcVar},NcVar);gatts::Dict{Any,Any}=Dict{Any,Any}(),mode::Uint16=NC_NETCDF4)
  ida=Array(Int32,1)
  vars=Dict{String,NcVar}();
  #Create the file
  _nc_create_c(name,mode,ida);
  id=ida[1];
  # Unify types
  if (typeof(varlist)==NcVar)
    varlist=[varlist]
  end
  # Collect Dimensions
  dims=Set{NcDim}();
  for v in varlist
    for d in v.dim
      push!(dims,d);
    end
  end
  nunlim=0;
  ndim=int32(length(dims));
  #Create Dimensions in the file
  dim=Dict{String,NcDim}();
  for d in dims
    dima=Array(Int32,1);
    NC_VERBOSE? println("Dimension length ", d.dimlen) : nothing
    _nc_def_dim_c(id,d.name,d.dimlen,dima);
    d.dimid=dima[1];
    dim[d.name]=d;
    #Create dimension variable
    if length(d.vals)>0
      varida=Array(Int32,1)
      dumids=[copy(d.dimid)]
      _nc_def_var_c(id,d.name,NC_DOUBLE,1,dumids,varida)
      putatt(id,varida[1],d.atts)
      d.varid=varida[1]
      dd=Array(NcDim,1)
      dd[1]=d
      vars[d.name]=NcVar(id,varida[1],1,length(d.atts),NC_DOUBLE,d.name,[d.dimid],dd,d.atts,-1)
    end
  end
  # Create variables in the file
  for v in varlist
    i=1
    for d in v.dim
      v.dimids[i]=d.dimid
      i=i+1
    end
    vara=Array(Int32,1);
    dumids=int32(v.dimids)
    NC_VERBOSE ? println(dumids) : nothing
    _nc_def_var_c(id,v.name,int32(v.nctype),v.ndim,int32(dumids[v.ndim:-1:1]),vara);
    v.varid=vara[1];
    vars[v.name]=v;
    if v.compress > -1
      if (NC_NETCDF4 & mode)== 0 
        warn("Compression only possible for NetCDF4 file format. Compression will be ingored.")
        v.compress=-1
      else
        v.compress=max(v.compress,9)
        _nc_def_var_deflate_c(int32(id),int32(v.varid),int32(1),int32(1),int32(v.compress));
      end
    end
    putatt(id,v.varid,v.atts)
  end
  # Put global attributes
  if !isempty(gatts)
    putatt(id,NC_GLOBAL,gatts)
  end
  # Leave define mode
  _nc_enddef_c(id)
  #Create the NcFile Object
  nc=NcFile(id,length(vars),ndim,0,vars,dim,Dict{Any,Any}(),0,name,NC_WRITE)
  currentNcFiles[abspath(nc.name)]=nc
  for d in nc.dim
    #Write dimension variable
    if (length(d[2].vals)>0)
      putvar(nc,d[2].name,d[2].vals)
    end
  end
  return(nc)
end

function vardef(fid::Integer,v::NcVar)
    _nc_redef(ncid)
    i=1
    for d in v.dim
      v.dimids[i]=d.dimid
      i=i+1
    end
    vara=Array(Int32,1);
    dumids=int32(v.dimids)
    NC_VERBOSE? println(dumids) : nothing
    _nc_def_var_c(id,v.name,v.nctype,v.ndim,int32(dumids[v.ndim:-1:1]),vara);
    v.varid=vara[1];
    vars[v.name]=v;
end

function close(nco::NcFile)
  #Close file
  _nc_close_c(nco.ncid) 
  delete!(currentNcFiles,abspath(nco.name))
  NC_VERBOSE? println("Successfully closed file ",nco.ncid) : nothing
  return nco.ncid
end


function open(fil::String; mode::Integer=NC_NOWRITE, readdimvar::Bool=false)
  # Open netcdf file
  ncid=_nc_op(fil,mode)
  NC_VERBOSE ? println(ncid) : nothing
  #Get initial information
  (ndim,nvar,ngatt,nunlimdimid)=_ncf_inq(ncid)
  NC_VERBOSE ? println(ndim,nvar,ngatt,nunlimdimid) : nothing
  #Create ncdf object
  ncf=NcFile(ncid,nvar-ndim,ndim,ngatt,Dict{String,NcVar}(),Dict{String,NcDim}(),Dict{Any,Any}(),nunlimdimid,abspath(fil),mode)
  #Read global attributes
  ncf.gatts=_nc_getatts_all(ncid,NC_GLOBAL,ngatt)
  #Read dimensions
  for dimid = 0:ndim-1
    (name,dimlen)=_nc_inq_dim(ncid,dimid)
    ncf.dim[name]=NcDim(ncid,dimid,-1,name,dimlen,[1:dimlen],Dict{Any,Any}())
  end
  #Read variable information
  for varid = 0:nvar-1
    (name,nctype,dimids,natts,vndim,isdimvar)=_ncv_inq(ncf,varid)
    if (isdimvar)
      ncf.dim[name].varid=varid
    end
    atts=_nc_getatts_all(ncid,varid,natts)
    vdim=Array(NcDim,length(dimids))
    i=1;
    for did in dimids
      vdim[i]=ncf.dim[getdimnamebyid(ncf,did)]
      i=i+1
    end
    ncf.vars[name]=NcVar(ncid,varid,vndim,natts,nctype,name,int(dimids[vndim:-1:1]),vdim[vndim:-1:1],atts,0)
  end
  readdimvar==true ? _readdimvars(ncf) : nothing
  currentNcFiles[abspath(ncf.name)]=ncf
  return ncf
end

# Define some high-level functions
# High-level functions for writing data to files
function ncread{T<:Integer}(fil::String,vname::String;start::Array{T}=Array(Int,0),count::Array{T}=Array(Int,0))
  nc = haskey(currentNcFiles,abspath(fil)) ? currentNcFiles[abspath(fil)] : open(fil)
  x  = readvar(nc,vname,start,count)
  return x
end
ncread{T<:Integer}(fil::String,vname::String,start::Array{T,1},count::Array{T,1})=ncread(fil,vname,start=start,count=count)
function ncread!{T<:Integer}(fil::String,vname::String,vals::Array;start::Array{T}=ones(Int,ndims(vals)),count::Array{T}=Array(Int,size(vals)))
  nc = haskey(currentNcFiles,abspath(fil)) ? currentNcFiles[abspath(fil)] : open(fil)
  x  = readvar!(nc,vname,vals,start=start,count=count)
  return x
end

function ncinfo(fil::String)
  nc= haskey(currentNcFiles,abspath(fil)) ? currentNcFiles[abspath(fil)] : open(fil)
  return(nc)
end

#High-level functions for writing data to a file
function ncwrite{T<:Integer}(x::Array,fil::String,vname::String;start::Array{T,1}=ones(Int,length(size(x))),count::Array{T,1}=[size(x)...])
  nc= haskey(currentNcFiles,abspath(fil)) ? currentNcFiles[abspath(fil)] : open(fil,mode=NC_WRITE)
  if (nc.omode==NC_NOWRITE)
    close(nc)
    println("reopening file in WRITE mode")
    open(fil,mode=NC_WRITE)
  end
  putvar(nc,vname,x,start=start,count=count)
end
ncwrite(x::Array,fil::String,vname::String,start::Array)=ncwrite(x,fil,vname,start=start)

function ncgetatt(fil::String,vname::String,att::String)
  nc= haskey(currentNcFiles,abspath(fil)) ? currentNcFiles[abspath(fil)] : open(fil,NC_WRITE)
  return ( haskey(nc.vars,vname) ? get(nc.vars[vname].atts,att,nothing) : get(nc.gatts,att,nothing) )
end

#High-level function for creating files and variables
# 
# if the file does not exist, it will be created
# if the file already exists, the variable will be added to the file

function nccreate(fil::String,varname::String,dims...;atts::Dict=Dict{Any,Any}(),gatts::Dict=Dict{Any,Any}(),compress::Integer=-1,t::Union(Integer,Type)=NC_DOUBLE,mode::Uint16=NC_NETCDF4)
  # Checking dims argument for correctness
  dim=parsedimargs(dims)
  # open the file
  # create the NcVar object
  v=NcVar(varname,dim,atts=atts,compress=compress,t=t)
  # Test if the file already exists
  if (isfile(fil)) 
    nc=haskey(currentNcFiles,abspath(fil)) ? currentNcFiles[abspath(fil)] : open(fil,mode=NC_WRITE)
    if (nc.omode==NC_NOWRITE)
      close(nc)
      println("reopening file in WRITE mode")
      open(fil,NC_WRITE)
    end
    haskey(nc.vars,varname) ? error("Variable $varname already exists in file fil") : nothing
    # Check if dimensions exist, if not, create
    i=1
    # Remember if dimension was created
    dcreate=Array(Bool,length(dim))
    for d in dim
      did=_nc_inq_dimid(nc.ncid,d.name)
      if (did==-1)
        dima=Array(Int32,1);
        #_nc_redef_c(nc.ncid)
        if (!nc.in_def_mode) 
          _nc_redef_c(nc.ncid)
          nc.in_def_mode=true
        end
        _nc_def_dim_c(nc.ncid,d.name,d.dimlen,dima);
        d.dimid=dima[1];
        v.dimids[i]=d.dimid;
        dcreate[i] = true
      else
        dcreate[i] = false
        v.dimids[i]=nc.dim[d.name].dimid;
        v.dim[i] = nc.dim[d.name]
      end
      i=i+1
    end
    # Create variable
    vara=Array(Int32,1);
    dumids=int32(v.dimids)
    if (!nc.in_def_mode) 
          _nc_redef_c(nc.ncid)
          nc.in_def_mode=true
    end
    _nc_def_var_c(nc.ncid,v.name,v.nctype,v.ndim,int32(dumids[v.ndim:-1:1]),vara);
    v.varid=vara[1];
    nc.vars[v.name]=v;
    putatt(nc.ncid,v.varid,atts)
    if (nc.in_def_mode) 
          _nc_enddef_c(nc.ncid)
          nc.in_def_mode=false
    end
    i=1
    for d in dim
      if (dcreate[i])
        ncwrite(d.vals,fil,d.name)
      end
      i=i+1
    end
  else
    nc=create(fil,v,gatts=gatts,mode=mode | NC_NOCLOBBER)
    for d in dim
      ncwrite(d.vals,fil,d.name)
    end
  end
end

function show(io::IO,nc::NcFile)
  println(io,"")
  println(io,"##### NetCDF File #####")
  println(io,"")
  println(io,nc.name)
  println(io,"")
  println(io,"##### Dimensions #####")
  println(io,"")
  @printf(io,"%15s %8s","Name","Length\n")
  println("-------------------------------")
  for d in nc.dim
    @printf(io,"%15s %8d\n",d[2].name,d[2].dimlen)
  end
  println(io,"")
  println(io,"##### Variables #####")
  println(io,"")
  @printf(io,"%20s%20s%20s\n","Name","Type","Dimensions")
  println("---------------------------------------------------------------")
  for v in nc.vars
    @printf(io,"%20s",v[2].name)
    @printf(io,"%20s          ",nctype2string[int(v[2].nctype)])
    for d in v[2].dim
      @printf(io,"%s, ",d.name)
    end
    @printf(io,"\n")
  end
  println(io,"")
  println(io,"##### Attributes #####")
  println(io,"")
  @printf(io,"%20s %20s %20s\n","Variable","Name","Value")
  println("---------------------------------------------------------------")
  for a in nc.gatts
    an=string(a[1])
    av=string(a[2])
    an=an[1:min(length(an),38)]
    av=av[1:min(length(av),38)]
    @printf(io,"%20s %20s %40s\n","global",an,av)
  end
  for v in nc.vars
    for a in v[2].atts
      an=string(a[1])
      av=string(a[2])
      vn=
      an=an[1:min(length(an),38)]
      av=av[1:min(length(av),38)]
      @printf(io,"%20s %20s %40s\n",v[2].name,an,av)
    end
  end

end

end # Module
