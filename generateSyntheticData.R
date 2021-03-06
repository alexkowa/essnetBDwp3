# Project: Test
# 
# Author: kowa$
###############################################################################
library(simPop);library(VIM)
# Eusilc Austria sample data
data(eusilcS)
# adjust the weights to get the "real" population
eusilcS$db090 <- eusilcS$db090*100 
inp <- specifyInput(data=eusilcS, hhid="db030", hhsize="hsize", strata="db040", weight="db090")
simPop <- simStructure(data=inp, method="direct", basicHHvars=c("age", "rb090"))
simPop <- simCategorical(simPop, additional=c("pl030", "pb220a"), method="multinom", nr_cpus=1)
simPop <- simContinuous(simPop, additional="netIncome",regModel = ~rb090+hsize+pl030+pb220a, upper=200000, equidist=FALSE, nr_cpus=1)
p <- copy(pop(simPop))
# Define somehow an equalized income
p[,eqIncome:=sum(netIncome)/max(c(1,sum(as.numeric(age%in%as.character(16:65))))),by="db030"]
#Create matching variables
p[,Age:=as.character(as.numeric(age))]
p[,NUM_CHILDREN_0_10:=sum(as.numeric(Age%in%c(0:10))),by=db030]
p[,NUM_CHILDREN_11_17:=sum(as.numeric(Age%in%c(11:17))),by=db030]
p[,NUM_OCCUPANTS:=hsize]
p[,NUM_OCCUPANTS_70PLUS:=sum(as.numeric(Age%in%c(70:99))),by=db030]
p[,IS_HOME_DURING_DAYTIME:="N"]
p[pl030%in%c(3,5,6,7),IS_HOME_DURING_DAYTIME:="Y"]
#Approx. distribution of the Income groups in Australian data replicated
p[,quantile(eqIncome,c(.25,.5))]
p[,HHOLD_INCOME_GROUP_CD:="HI"]
p[eqIncome<20599,HHOLD_INCOME_GROUP_CD:="MED"]
p[eqIncome<13641,HHOLD_INCOME_GROUP_CD:="LOW"]
anyY <- function(x){
  if(any(x=="Y"))
    return("Y")
  else
    return("N")
}
p[,IS_HOME_DURING_DAYTIME:=anyY(IS_HOME_DURING_DAYTIME),by=db030]

library(data.table);

###Smart Meter data Australia
#Customer data
cust <- fread("/hdfs/datasets/smartmeters/customers/customers.csv")
matchVar <- intersect(colnames(cust),colnames(p))
#Data set of "Austrian" households
h <- p[!duplicated(db030),c(matchVar,"db030"),with=FALSE]
cust <- na.omit(cust[,c(matchVar,"CUSTOMER_KEY"),with=FALSE])
cust[HHOLD_INCOME_GROUP_CD%in%c("DeclinedToAnswer",""),HHOLD_INCOME_GROUP_CD:=NA]
##Create factor variables
cust[,HHOLD_INCOME_GROUP_CD:=factor(HHOLD_INCOME_GROUP_CD)]
h[,HHOLD_INCOME_GROUP_CD:=factor(HHOLD_INCOME_GROUP_CD)]
cust[,IS_HOME_DURING_DAYTIME:=factor(IS_HOME_DURING_DAYTIME)]
h[,IS_HOME_DURING_DAYTIME:=factor(IS_HOME_DURING_DAYTIME)]
#Impute missing income groups
cust[,HHOLD_INCOME_GROUP_CD:=kNN(cust,imp_var = FALSE)$HHOLD_INCOME_GROUP_CD]
#Initialize empty customer key variable
h[,CUSTOMER_KEY:=NA]
hx <- rbind(h,cust,fill=TRUE)

# redefine collumns and set as factor for primitive imputation
hx[,c("NUM_OCCUPANTS","NUM_CHILDREN_0_10","NUM_CHILDREN_11_17","NUM_OCCUPANTS_70PLUS"):=list(as.character(NUM_OCCUPANTS),
                                                                                             as.character(NUM_CHILDREN_0_10),
                                                                                             as.character(NUM_CHILDREN_11_17),
                                                                                             as.character(NUM_OCCUPANTS_70PLUS))]
hx[NUM_OCCUPANTS>"4",NUM_OCCUPANTS:="5+"]
hx[NUM_CHILDREN_0_10>"0",NUM_CHILDREN_0_10:="1+"]
hx[NUM_CHILDREN_11_17>"0",NUM_CHILDREN_11_17:="1+"]
hx[NUM_OCCUPANTS_70PLUS>"0",NUM_OCCUPANTS_70PLUS:="1+"]

hx[,c("NUM_OCCUPANTS","NUM_CHILDREN_0_10","NUM_CHILDREN_11_17","NUM_OCCUPANTS_70PLUS"):=list(factor(NUM_OCCUPANTS),
                                                                                             factor(NUM_CHILDREN_0_10),
                                                                                             factor(NUM_CHILDREN_11_17),
                                                                                             factor(NUM_OCCUPANTS_70PLUS))]
primitive.impute <- function(x){
  # function for primitive imputation
  x.na <- is.na(x)
  
  if(all(!x.na)){
    return(x)
  }
  
  if(all(x.na)){
    warning("no donors present in subsample")
    return(x)
  }
  n.imp <- sum(x.na)
  if(length(x[!x.na])>1){
    x[x.na] <- sample(x[!x.na],n.imp,replace=TRUE)
  }else{
    x[x.na] <- x[!x.na]
  }
  
  return(x)
}

# apply primitive.impute until no NAs are present anymore
# leaf out one collumn name for each iteration
matchVar <- matchVar[c(1,2,6,4,3,5)]

index <- any(is.na(hx$CUSTOMER_KEY))
i <- length(matchVar)+1
while(index){
  i <- i-1
  hx[,CUSTOMER_KEY:=primitive.impute(CUSTOMER_KEY),by=c(matchVar[1:i])]
  index <- any(is.na(hx$CUSTOMER_KEY))
}
hy <- hx[!is.na(db030)]

save(hy,file="hhWithCustomerKey.RData",compress=TRUE)
rm(h,hx,p,simPop);gc()

smr <- fread("/hdfs/datasets/smartmeters/metering_data/metering_data.csv")
smr <- smr[CUSTOMER_ID%in%cust[,CUSTOMER_KEY],]
setnames(smr,"CUSTOMER_ID","CUSTOMER_KEY")
setkey(smr,CUSTOMER_KEY)
#Remove unnecessary vars
smr[,c("EVENT_KEY","CALENDAR_KEY","CONTROLLED_LOAD_KWH","GROSS_GENERATION_KWH",
       "NET_GENERATION_KWH","OTHER_KWH"):=NULL]
#only keep 1 year (2013)
smr smr[year(READING_DATETIME)==2013]
gc()




