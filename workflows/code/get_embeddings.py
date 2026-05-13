# Requires to install redivis in the environment.
# First time you run this, it will ask you to web auth on redivis and create an account
import redivis

user = redivis.user("sdss_data_repository")
dataset = user.dataset("mosaiks:8bqm:v1_0")
table = dataset.table("0_25_x_0_25_deg_grid:76p8")


# This table contains file references, to download:
table.download_files("../input/mosaiks_0_25.csv")
